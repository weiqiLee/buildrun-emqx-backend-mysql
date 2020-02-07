%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
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
%%--------------------------------------------------------------------

-module(buildrun_emqx_backend_mysql).

-include_lib("buildrun_emqx_backend_mysql.hrl").
-include_lib("emqx/include/emqx.hrl").

-define(CLIENT_CONNECTED_SQL,
    <<"insert into mqtt_client(clientid, state, "
                   "node, online_at, offline_at) values(?, "
                   "null, null, now(), null) on duplicate key "
                   "update state = null, node = null, online_at "
                   "= now(), offline_at = null">>).
-define(CLIENT_DISCONNECTED_SQL,
                 <<"update mqtt_client set state = ?, offline_at "
                   "= now() where clientid = ?">>).

-define(MESSAGE_PUBLISH_SQL,
                 <<"insert into mqtt_msg(msgid, sender, "
                   "topic, qos, retain, payload, arrived) "
                   "values (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))">>).

-define(MESSAGE_RETAIN_SQL,
                 <<"insert into mqtt_retain(topic, msgid, "
                   "sender, qos, payload, arrived) values "
                   "(?, ?, ?, ?, ?, FROM_UNIXTIME(?))on "
                   "duplicate key  update msgid = ?, sender "
                   "= ?, qos = ?, payload = ?, arrived = "
                   "FROM_UNIXTIME(?)">>).             


-export([ load/1
        , unload/0
        ]).

%% Client Lifecircle Hooks
-export([ on_client_connected/3
        , on_client_disconnected/4
        ]).


%% Message Pubsub Hooks
-export([ on_message_publish/2
        ]).

%% Called when the plugin application start
load(Env) ->
    emqx:hook('client.connected',    {?MODULE, on_client_connected, [Env]}),
    emqx:hook('client.disconnected', {?MODULE, on_client_disconnected, [Env]}),
    emqx:hook('message.publish',     {?MODULE, on_message_publish, [Env]}).

%%--------------------------------------------------------------------
%% Client Lifecircle Hooks
%%--------------------------------------------------------------------

on_client_connected(ClientInfo = #{clientid := ClientId}, ConnInfo, _Env) ->
    buildrun_emqx_backend_mysql_cli:query(?CLIENT_CONNECTED_SQL, [binary_to_list(ClientId)]),
    io:format("Client(~s) connected, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
            [ClientId, ClientInfo, ConnInfo]).
        

on_client_disconnected(ClientInfo = #{clientid := ClientId}, ReasonCode, ConnInfo, _Env) ->
    io:format("Client(~s) disconnected due to ~p, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
              [ClientId, ReasonCode, ClientInfo, ConnInfo]).

%%--------------------------------------------------------------------
%% Message PubSub Hooks
%%--------------------------------------------------------------------

%% Transform message and return
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message, _Env) ->
    io:format("Publish ~s~n", [emqx_message:format(Message)]),
    {ok, Message}.


%% Called when the plugin application stop
unload() ->
    emqx:unhook('client.connected',    {?MODULE, on_client_connected}),
    emqx:unhook('client.disconnected', {?MODULE, on_client_disconnected}),
    emqx:unhook('message.publish',     {?MODULE, on_message_publish}).


