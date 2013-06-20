-module(smart_eredis_algorithm).

-callback init( PoolName ::atom(), 
                InitOption :: list()) ->
    ok | {error, Reason :: term()}.


-callback get_client_id( PoolName :: atom(), 
                         Key     :: string(), 
                         Options :: list()) ->
    ok | {error, Reason :: term()}.