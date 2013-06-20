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

-record(scheduling,  { algorithm         :: atom(), 
                       runtime_options   :: list()
                      }).

-define(TAB_CONFIG,      ets_smart_eredis_config).

-endif.