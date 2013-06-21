%% -------------------------------------------------------------------
%% Copyright (c) 2013 Xujin Zheng (zhengxujin@adsage.com)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% -------------------------------------------------------------------

-module(component_eredis_pool).
-behaviour(mini_pool_component).

-include("smart_eredis.hrl").
-include_lib("mini_pool/include/mini_pool.hrl").

-export([on_event/2, recover/2, start/1]).

on_event(_Msg, _Option) -> ok.

recover({Id, _Reason}, Servers) ->
    S = [Server|| #redis{id = RedisId} = Server <- Servers, RedisId =:= Id],
    case head(S) of
        undefined ->
            ignore;
        Server ->
            case connect_to_server(Server) of 
                {ok, {Id, Pid}} ->
                    {ok, Pid};
                Error ->
                    Error 
            end
    end.

head([])-> undefined;
head([H|_T]) ->H.    

start(Servers) ->
    connect_to_servers(Servers, []).

connect_to_servers([], AccOutPids) -> {ok, AccOutPids};
connect_to_servers([Server|Servers], AccOutPids) ->
    AccOut = 
    case connect_to_server(Server) of 
        {ok, {Id, Pid}} ->
            [{Id, Pid}|AccOutPids];
        _->
            AccOutPids
    end,
    connect_to_servers(Servers, AccOut).

connect_to_server(Server) when is_record(Server, redis)->
    #redis{ id       = Id,
            host     = Host, 
            port     = Port,
            database = Db,
            password = Password} = Server,
    {ok, Pid} = eredis:start_link(Host, Port, Db, Password),
    {ok, {Id, Pid}}.