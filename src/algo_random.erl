-module(algo_random).

-behaviour(smart_eredis_algorithm).

-export([init/2, get_client_id/3]).

init(_PoolName, _Options)->
    ok.

get_client_id(_PoolName, _Key, Options)->
    Ids = util_plist:get_value(ids, Options, []),
    Len = length(Ids),
    case Len > 0 of
        true ->
            random:seed(os:timestamp()),
            {ok, random:uniform(Len)};
        false ->
            {error, no_random_ids}
    end.