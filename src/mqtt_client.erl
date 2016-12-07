%%
%% Copyright (C) 2015-2016 by krasnop@bellsouth.net (Alexei Krasnopolski)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License. 
%%

%% @since 2015-12-25
%% @copyright 2015-2016 Alexei Krasnopolski
%% @author Alexei Krasnopolski <krasnop@bellsouth.net> [http://krasnopolski.org/]
%% @version {@version}
%% @doc Main module of mqtt_client application. The module implements application behaviour
%% and application API.
%% @headerfile "mqtt_client.hrl"

-module(mqtt_client).
-behaviour(application).

%%
%% Include files
%%
-include("mqtt_client.hrl").

-export([start/2, stop/1]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([
	connect/5,
	connect/6,
	status/1,
	publish/2,
	publish/3,
	subscribe/2,
	unsubscribe/2,
	pingreq/2,
	disconnect/1
]).
%% <dl>
%% <dt></dt>
%% <dd></dd>
%% </dl>


-spec connect(Connection_id, Conn_config, Host, Port, Socket_options) -> Result when
  Connection_id :: atom(),
  Conn_config :: #connect{},
  Host :: string(),
  Port :: integer(),
  Socket_options :: list(),
  Result :: pid() | #mqtt_client_error{}.
%% 
%% @doc The function creates socket connection to MQTT server and sends connect package to the server.
%% <dl>
%% <dt>Connection_id</dt>
%% <dd>Registered name of connection process.</dd>
%% <dt>Conn_config</dt>
%% <dd>#connect{} record defines the connection options.</dd>
%% <dt>Host</dt>
%% <dd>IP or host name of MQTT server.</dd>
%% <dt>Port</dt>
%% <dd>port number of MQTT server.</dd>
%% <dt>Socket_options</dt>
%% <dd>Additional socket options.</dd>
%% </dl>
%% Returns Pid of new created connection process. 
%%
connect(Connection_id, Conn_config, Host, Port, Socket_options) ->
  connect(Connection_id, Conn_config, Host, Port, undefined, Socket_options).

-spec connect(Connection_id, Conn_config, Host, Port, Default_Callback, Socket_options) -> Result when
 Connection_id :: atom(),
 Conn_config :: #connect{},
 Host :: string(),
 Port :: integer(),
 Default_Callback :: {atom()} | {atom(), atom()},
 Socket_options :: list(),
 Result :: pid() | #mqtt_client_error{}.
%% 
%% @doc The function creates socket connection to MQTT server and sends connect package to the server.<br/>
%% Parameters:
%% <ul style="list-style-type: none;">
%% <li>Connection_id - Registered name of connection process.</li>
%% <li>Conn_config - #connect{} record defines the connection options.</li>
%% <li>Host - IP or host name of MQTT server.</li>
%% <li>Port - port number of MQTT server.</li>
%% <li>Default_Callback - Definition of callback function for any subscriptions what miss callback definition.</li>
%% <li>Socket_options - Additional socket options.</li>
%% </ul>
%% Returns Pid of new created connection process. 
%%
connect(Connection_id, Conn_config, Host, Port, Default_Callback, Socket_options) ->
	%% @todo check input parameters
	case mqtt_client_sup:new_connection(Connection_id, Host, Port, Socket_options) of
		{ok, Pid} ->
			{ok, Ref} = gen_server:call(Pid, {connect, Conn_config, Default_Callback}, ?GEN_SERVER_TIMEOUT),
			receive
				{connectack, Ref, _SP, 0, _Msg} -> 
%					io:format(user, " >>> client ~p/~p session present: ~p connected with response: ~p, ~n", [Pid, Conn_config, _SP, _Msg]),
					Pid;
				{connectack, Ref, _, ErrNo, Msg} -> 
%					io:format(user, " >>> client ~p connected with response: ~p, ~n", [Pid, Msg]),
					#mqtt_client_error{type = connection, errno = ErrNo, source = "mqtt_client:conect/6", message = Msg}
			after ?GEN_SERVER_TIMEOUT ->
					#mqtt_client_error{type = connection, source = "mqtt_client:conect/6", message = "timeout"}
			end;
		#mqtt_client_error{} = Error -> Error;
		Exit ->
			io:format(user, " >>> client catched: ~p, ~n", [Exit])
	end.

-spec status(Pid) -> Result when
 Pid :: pid(),
 Result :: disconnected | [{session_present, SP:: 0 | 1} | 
                         {subscriptions, #{Topic::string() => {QoS::integer(), Callback::{fun()} | {module(), fun()}}}}].
%% @doc The function returns status of connection with pid = Pid.
%% 
status(Pid) ->
	case is_process_alive(Pid) of
		true ->
			try
				gen_server:call(Pid, status, ?GEN_SERVER_TIMEOUT)
			catch
				_:_ -> disconnected
			end;
		false -> disconnected
	end.

-spec publish(Pid, Params, Payload) -> Result when
 Pid :: pid(),
 Params :: #publish{}, 
 Payload :: binary(),
 Result :: ok | puback | pubcomp | #mqtt_client_error{}. 
%% 
%% @doc The function sends a publish packet to MQTT server.
%% 
publish(Pid, Params, Payload) ->
  publish(Pid, Params#publish{payload = Payload}).	
	
-spec publish(Pid, Params) -> Result when
 Pid :: pid(),
 Params :: #publish{}, 
 Result :: ok | puback | pubcomp | #mqtt_client_error{}. 
%% 
%% @doc The function sends a publish packet to MQTT server.
%% 
publish(Pid, Params) -> 
	case gen_server:call(Pid, {publish, Params}, ?GEN_SERVER_TIMEOUT) of
		{ok, Ref} -> 
			case Params#publish.qos of
				0 -> ok;
				1 ->
					receive
						{puback, Ref} -> 
%					io:format(user, " >>> received puback ~p~n", [Ref]), 
							puback
					after ?GEN_SERVER_TIMEOUT ->
						#mqtt_client_error{type = publish, source = "mqtt_client:publish/2", message = "puback timeout"}
					end;
				2 ->
					receive
						{pubcomp, Ref} -> 
%					io:format(user, " >>> received pubcomp ~p~n", [Ref]),
							pubcomp
					after ?GEN_SERVER_TIMEOUT ->
						#mqtt_client_error{type = publish, source = "mqtt_client:publish/2", message = "pubcomp timeout"}
					end
			end;
		{error, Reason} ->
				#mqtt_client_error{type = publish, source = "mqtt_client:publish/2", message = Reason}
  end.

-spec subscribe(Pid, Subscriptions) -> Result when
 Pid :: pid(),
 Subscriptions :: [{Topic::string(), QoS::integer(), Callback::{fun()} | {module(), fun()} }], 
 Result :: {suback, [integer()]} | #mqtt_client_error{}. 
%% 
%% @doc The function sends a subscribe packet to MQTT server.
%% 
subscribe(Pid, Subscriptions) ->
	{ok, Ref} = gen_server:call(Pid, {subscribe, Subscriptions}, ?GEN_SERVER_TIMEOUT), %% @todo can return {error, Reason}
	receive
		{suback, Ref, RC} -> 
%			io:format(user, " >>> received suback ~p~n", [RC]), 
			{suback, RC}
	after ?GEN_SERVER_TIMEOUT ->
		#mqtt_client_error{type = subscribe, source = "mqtt_client:subscribe/2", message = "subscribe timeout"}
	end.

-spec unsubscribe(Pid, Topics) -> Result when
 Pid :: pid(),
 Topics :: [Topic::string()], 
 Result :: unsuback | #mqtt_client_error{}. 
%% 
%% @doc The function sends a subscribe packet to MQTT server.
%% 
unsubscribe(Pid, Topics) ->
	{ok, Ref} = gen_server:call(Pid, {unsubscribe, Topics}, ?GEN_SERVER_TIMEOUT), %% @todo can return {error, Reason}
	receive
		{unsuback, Ref} -> 
%			io:format(user, " >>> received unsuback ~p~n", [Ref]), 
			unsuback
	after ?GEN_SERVER_TIMEOUT ->
		#mqtt_client_error{type = subscribe, source = "mqtt_client:unsubscribe/2", message = "unsubscribe timeout"}
	end.

-spec pingreq(Pid, Callback) -> Result when
 Pid :: pid(),
 Callback :: {fun()} | {module(), fun()},
 Result :: ok. 
%% 
%% @doc The function sends a ping request to MQTT server.
%% 
pingreq(Pid, Callback) -> 
	gen_server:call(Pid, {ping, Callback}, ?GEN_SERVER_TIMEOUT).

-spec disconnect(Pid) -> Result when
 Pid :: pid(),
 Result :: none() | {error, Reason::term()}. 
%% 
%% @doc The function sends a disconnect request to MQTT server.
%% 
disconnect(Pid) ->
	try 
  	gen_server:call(Pid, disconnect, ?GEN_SERVER_TIMEOUT)
	catch
    exit:_R -> 
%			io:format(user, " >>> disconnect: exit reason ~p~n", [_R]),
			ok
	end.

%% ====================================================================
%% Behavioural functions
%% ====================================================================

%% start/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/apps/kernel/application.html#Module:start-2">application:start/2</a>
%% @private
-spec start(Type :: normal | {takeover, Node} | {failover, Node}, Args :: term()) ->
	{ok, Pid :: pid()}
	| {ok, Pid :: pid(), State :: term()}
	| {error, Reason :: term()}.
%% ====================================================================
start(_Type, StartArgs) ->
%  io:format(user, " >>> start application ~p ~p~n", [_Type, StartArgs]),
  case supervisor:start_link({local, mqtt_client_sup}, mqtt_client_sup, StartArgs) of
		{ok, Pid} ->
			{ok, Pid};
		Error ->
			Error
    end.

%% stop/1
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/apps/kernel/application.html#Module:stop-1">application:stop/1</a>
-spec stop(State :: term()) ->  Any :: term().
%% ====================================================================
%% @private
stop(_State) ->
%  io:format(user, " <<< stop application ~p~n", [_State]),
  ok.

%% ====================================================================
%% Internal functions
%% ====================================================================

