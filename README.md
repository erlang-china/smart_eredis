smart_eredis
======
smart eredis based on eredis, and add external algorithm for redis sharding, 
currently, we provide two algorithm: `ketama` and `random`.

The following **smart_eredis.config** has two pool, the `pool_1` are 
using ketama algorithm to sharding the keys, and there has two working node, 
and one debug node, the `pool_2` are using random algorithm you can random to 
access every redis server, it is good scenario for read operation with 
redis(slave), and it can load balance the redis-server's load. 


**working node:** normally using redis node.

**debug node  :** record every key accessed frequency.
>  e.g. 
>  if you want to access pool_1 to set a key, then the algorithm will help you 
>  to find the real redis server, then the key will store in the redis node, 
>  if you enabled the debug mode, this key will also store in debug redis node, 
>  but the value is the key `accessed count` and the `latest accessed time`

#### config

```erlang
{smart_eredis, 
    [{pools,
        [
            %% {pool_name            :: atom(), 
            %%  servers              :: list(), 
            %%  scheduling_algorithm :: list(), 
            %%  options              :: list()}
            {pool_1,[
                        [{id, 1}, 
                         {host, "127.0.0.1"}, 
                         {port, 6379}, 
                         {database, 1}, 
                         {password, ""}], 
                        [{id, 2},
                         {host, "127.0.0.1"}, 
                         {port, 6380}, 
                         {database, 1}, 
                         {password, ""}],
                        [{id, debug}, 
                         {host, "127.0.0.1"}, 
                         {port, 6380}, 
                         {database, 0}, 
                         {password, ""}]
                    ], 
                    
                    %% [ALGORITHM_MODULE, INIT_OPTIONS, RUNTIME_OPTIONS]
                    %% init option: while load this pool, it will use 
                    %% this option to initial ketama algorithm
                    %% runtime option: this parameter are using in every 
                    %% request, see example of random
                    [ {algorithm, algo_ketama},
                      {init_options,
                            [{ring_opt, [{expand_node, false},
                                         {match_operator, '>'},
                                         {concat_char, ":"},
                                         {copies_gen_type, specific}]},
                             {nodes, [{1, "redis:node_001:6379", 100, 1},
                                      {2, "redis:node_001:6380", 100, 2}]}]},
                      {runtime_options, []}
                    ],
                    [{debug, true}]
            },
            {pool_2,[
                        [{id, 1}, 
                         {host, "127.0.0.1"}, 
                         {port, 6379}, 
                         {database, 1}, 
                         {password, ""}], 
                        [{id, 2}, 
                         {host, "127.0.0.1"}, 
                         {port, 6380}, 
                         {database, 1}, 
                         {password, ""}],
                        [{id, debug}, 
                         {host, "127.0.0.1"}, 
                         {port, 6380}, 
                         {database, 0}, 
                         {password, ""}]
                    ],
                    [
                        {algorithm, algo_random},
                        {init_options, []},
                        {runtime_options, [{ids, [1,2]}]}
                    ],
                    [{debug, true}]
            }
        ]}
    ]
}.
```

#### usage:
tiny different of eredis, it is not necessary to use Client(pid), 
and you need show clearly the key 
in the scecond parameter

***eredis***
```erlang
{ok, <<"OK">>} = eredis:q(C, ["SET", "foo", "bar"]).
```

***smart_eredis***
```erlang
{ok, <<"OK">>} = smart_eredis:q(pool_1, "foo", ["SET", "foo", "bar"]).
```

#### customize your own algorithm
you need to implament following behavior
```erlang
-module(smart_eredis_algorithm).

-callback init( PoolName ::atom(), 
                InitOption :: list()) ->
    ok | {error, Reason :: term()}.


-callback get_client_id( PoolName :: atom(), 
                         Key     :: string(), 
                         Options :: list()) ->
    ok | {error, Reason :: term()}.
```

***example:***
```erlang
-module(algo_random).

-behaviour(smart_eredis_algorithm).

-export([init/2, get_client_id/3]).

init(_PoolName, _Options)->
    ok.


%% {algorithm, algo_random},
%% {init_options, []},
%% {runtime_options, [{ids, [1,2]}]}
get_client_id(_PoolName, _Key, Options)->
    Ids = proplists:get_value(ids, Options, []),
    Len = length(Ids),
    case Len > 0 of
        true ->
            random:seed(os:timestamp()),
            {ok, random:uniform(Len)};
        false ->
            {error, no_random_ids}
    end.
```