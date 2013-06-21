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

-ifndef(SMART_EREDIS_H).
-define(SMART_EREDIS_H, true).

-record(redis, {id       = 0           :: atom() | integer(), 
                host     = "127.0.0.1" :: string(), 
                port     = 6379        :: integer(), 
                database = 0           :: integer(), 
                password = ""          :: string()}).

-record(smart_eredis, {name            :: atom(),
                       servers = []    :: list(), 
                       debug   = false :: boolean(), 
                       scheduling
                      }).

-record(scheduling,  { get_client_id :: fun((atom(), string(), list()) ->
                                                      ok | {error, term()}), 
                       runtime_options   :: list()
                      }).

-define(TAB_CONFIG, ets_smart_eredis_config).

-endif.