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
    erlang:send_after(100, smart_eredis, {eredis_keeper_sup, init}),
    {ok, { {one_for_one, 5, 10}, []} }.