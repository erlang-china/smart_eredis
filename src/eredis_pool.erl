-module(eredis_pool).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("eredis_pool.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([start_pool/1, 
         stop_pool/1]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start_pool(Pool) when is_record(Pool, eredis_pool)->
    gen_server:call(?MODULE, {start_pool, Pool}).

stop_pool(PoolName) when is_atom(PoolName)->
    gen_server:call(?MODULE, {stop_pool, PoolName}).


%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {}).

init([]) ->
    ?TAB_CLIENT_PIDS = ets_mgr:soft_new(?TAB_CLIENT_PIDS, 
                                        [named_table,
                                        protected,
                                        {keypos, 1},
                                        {write_concurrency, false}, 
                                        {read_concurrency,  true}]),
    {ok, #state{}}.

handle_call({start_pool, Pool}, _From, State) when is_record(Pool, eredis_pool)->
    Reply = internal_start_pool(Pool),
    {reply, Reply, State};
handle_call({stop_pool, PoolName}, _From, State) ->
    Reply = internal_stop_pool(PoolName),
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = {error, unknown_request},
    {reply, Reply, State}.

handle_cast({on_eredis_client_update, PoolName, ChildId, NewClientPid}, State) ->
    on_eredis_client_update(PoolName, ChildId, NewClientPid),
    {noreply, State};
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
    case whereis(?KEEPER_SUP) of
        Pid when is_pid(Pid)->  
            case supervisor:start_child(?KEEPER_SUP,
                                        {PoolName, {eredis_keeper, 
                                                    start_link, 
                                                    [Pool]},
                                        permanent, 
                                        5000, 
                                        worker, 
                                        [eredis_keeper]}) of 
                {ok, Pid} ->
                    {ok, Pid};
                {error, {already_started, Pid}} ->
                    {ok, Pid};
                Error->
                    Error
            end;
        _->
            {error, eredis_keeper_sup_not_started}
    end.

internal_stop_pool(PoolName)->
    case is_pool_exists(PoolName) of
        true->
            supervisor:terminate_child(?KEEPER_SUP, PoolName),
            supervisor:delete_child(?KEEPER_SUP, PoolName);
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

on_eredis_client_update(PoolName, ChildId, NewClientPid) ->
    ets:insert(?TAB_CLIENT_PIDS, {{PoolName, ChildId}, NewClientPid}).