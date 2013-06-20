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