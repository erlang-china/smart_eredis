-ifndef(EREDIS_POOL_H).
-define(EREDIS_POOL_H, true).

-record(redis, {id       = 0           :: atom() | integer(), 
                host     = "127.0.0.1" :: string(), 
                port     = 6379        :: integer(), 
                database = 0           :: integer(), 
                password = ""          :: string()}).

-record(eredis_pool, {name            :: atom(),
                      servers = []    :: list(), 
                      debug   = false :: boolean(), 
                      scheduling
                      }).

-record(scheduling,  { algorithm :: atom(), 
                       options   :: list()
                      }).

-define(TAB_CONFIG, ets_smart_eredis_config).
-define(KEEPER_SUP, eredis_keeper_sup).

-endif.