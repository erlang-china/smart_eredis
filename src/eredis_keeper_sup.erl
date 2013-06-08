-module(eredis_keeper_sup).

-behaviour(supervisor).

-include("eredis_pool.hrl").
%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    Pools    = get_pools_from_ets(),
    Children = 
    [pool_to_child_spec(Pool) ||Pool<- Pools],
    {ok, { {one_for_one, 50, 100}, Children}}.

get_pools_from_ets()->
    ets:match_object(?TAB_CONFIG, '$1').

pool_to_child_spec(Pool) when is_record(Pool, eredis_pool)->
    #eredis_pool{name = PoolName} = Pool,
    {PoolName, {eredis_keeper, 
                start_link, 
                [Pool]},
                permanent, 
                5000, 
                worker, 
                [eredis_keeper]}.