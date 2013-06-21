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