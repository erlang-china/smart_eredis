-module(eredis_pool).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("eredis_pool.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([start_pool/1, 
         stop_pool/1, 
         restart_pool/1,
         get_client/2,
         all_clients/1]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start_pool(Pool) when is_record(Pool, eredis_pool)->
    gen_server:call(?MODULE, {start_pool, Pool}).

stop_pool(PoolName) when is_atom(PoolName)->
    gen_server:call(?MODULE, {stop_pool, PoolName}).

restart_pool(PoolName) when is_atom(PoolName)->
    gen_server:call(?MODULE, {restart_pool, PoolName}).

get_client(PoolName, Id) when is_atom(PoolName)->
    eredis_keeper:get_client(PoolName, Id).

all_clients(PoolName) when is_atom(PoolName)->
    eredis_keeper:all_clients(PoolName).

%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {}).

init([]) ->
    %erlang:send_after(0, self(), {init}),
    {ok, #state{}}.

handle_call({restart_pool, PoolName}, _From, State)  when is_atom(PoolName)->
    Reply = internal_restart_pool(PoolName),
    {reply, Reply, State};
handle_call({start_pool, Pool}, _From, State) when is_record(Pool, eredis_pool)->
    Reply = internal_start_pool(Pool),
    {reply, Reply, State};
handle_call({stop_pool, PoolName}, _From, State) ->
    Reply = internal_stop_pool(PoolName),
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = {error, unknown_request},
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================
internal_start_pool(Pool) when is_record(Pool, eredis_pool) ->
    #eredis_pool{name = PoolName} = Pool,
    case is_pool_exists(PoolName) of 
        false->
            supervisor:start_child(?KEEPER_SUP,
                                    {PoolName, {eredis_keeper, 
                                                start_link, 
                                                [Pool]},
                                    permanent, 
                                    5000, 
                                    worker, 
                                    [eredis_keeper]});

        true->
            internal_restart_pool(PoolName)
    end.

internal_stop_pool(PoolName)->
    case is_pool_exists(PoolName) of
        true->
            supervisor:terminate_child(?KEEPER_SUP, PoolName);
        false->
            ok
    end.

internal_restart_pool(PoolName)->
    case is_pool_exists(PoolName) of
        true->
            supervisor:restart_child(?KEEPER_SUP, PoolName);
        false->
            ok
    end.

is_pool_exists(PoolName) ->
    MatchedSups =
    [{Id, Child, Type, Modules} 
     ||{Id, Child, Type, Modules} 
        <- get_sup_children(?KEEPER_SUP), 
        Id =:= PoolName],
    length(MatchedSups) > 0.

get_sup_children(SupName) ->
    Sups0 = (catch supervisor:which_children(SupName)),
    case Sups0 of 
        {'EXIT', _} ->
            [];
        Sups ->
            Sups
    end.