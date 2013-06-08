-module(smart_eredis).

-include("eredis_pool.hrl").

-behaviour(gen_server2).

-export([start_link/0]).

-export([start/0, stop/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([all_clients/0, all_clients/1, get_client/2]).

-export([all_pools/0, get_pool/1]).

-export([start_pool/1, stop_pool/1]).

%%eredis proxy
-export([q/3, q/4, qp/3, qp/4, q_noreply/3]).

-define(SERVER, ?MODULE).

%% eredis timeout
-define(TIMEOUT, 5000).

-record(state, {}).

start_link() ->
    gen_server2:start_link({local, ?SERVER}, ?MODULE, [], []).

start() ->
    ensure_started(ets_mgr),
    application:start(?MODULE).

stop() ->
    application:stop(?MODULE).

start_pool(Pool) when is_record(Pool, eredis_pool) ->
    gen_server:call(?MODULE,{start_pool, Pool}).

stop_pool(PoolName) when is_atom(PoolName)->
    gen_server:call(?MODULE,{stop_pool, PoolName}).

all_pools()->
    ets:match_object(?TAB_CONFIG, '$1').

get_pool(PoolName) ->
    case ets:lookup(?TAB_CONFIG, PoolName) of 
        [Object]->
            {ok, Object};
        _->
            {error, pool_not_found}
    end.

all_clients() ->
    ets:match_object(?TAB_CLIENT_PIDS, '$1').

all_clients(PoolName) ->
    ets:match_object(?TAB_CLIENT_PIDS, {{PoolName, '_'}, '_'}).

get_client(PoolName, Id) ->
    case ets:lookup(?TAB_CLIENT_PIDS, {PoolName, Id}) of 
        [{{PoolName, Id}, Client}] ->
            {ok, Client};
        _->
            {error , not_found}
    end.    

%% @private
init([]) ->
    case init_envs() of 
        ok->
            init_config_table(),
            Pools = get_pools_models(),
            true  = ets:insert(?TAB_CONFIG, Pools);
        {error, Reason} ->
            error_logger:error_msg("load config error:~n~p~n", [Reason])
    end,
    {ok, #state{}}.

handle_call({start_pool, Pool}, _From, State) when is_record(Pool, eredis_pool)->
    Reply = 
    case eredis_pool:start_pool(Pool) of
        {ok, Pid} ->
            true = ets:insert(?TAB_CONFIG, Pool),
            {ok, Pid};
        Error ->
            Error
    end,
    {reply, Reply, State};
handle_call({stop_pool, PoolName}, _From, State) ->
    Reply = 
    case eredis_pool:stop_pool(PoolName) of
        ok ->
            ets:delete(?TAB_CONFIG, PoolName),
            ok;
        Error ->
            Error
    end,
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok
    end.

init_envs() ->
    {ok, FileName} = application:get_env(config),
    init_envs(FileName).

init_envs(FileName) ->
    util_misc:load_app_env(smart_eredis, FileName, [config]).


init_config_table() ->
    ?TAB_CONFIG = ets_mgr:soft_new(?TAB_CONFIG, [ named_table,
                                         protected,
                                         {keypos, #eredis_pool.name},
                                         {write_concurrency, false}, 
                                         {read_concurrency,  true}]),
    ok.

get_pools_models() ->
    {ok, PoolsOptions}  = get_env(pools),
    [begin
        {PoolName, Servers, Scheduling, Options} = Pool,
        FormattedServer = 
        [ begin 
        Id   = util_plist:get_value(id,       Server),
        Host = util_plist:get_value(host,     Server),
        Port = util_plist:get_value(port,     Server),
        Db   = util_plist:get_value(database, Server),
        Pwd  = util_plist:get_value(password, Server),
        #redis{ id       = Id, 
                host     = Host, 
                port     = Port, 
                database = Db, 
                password = Pwd }
        end||Server <- Servers],
        IfDebugging = util_plist:get_value(debug, Options, false),

        Algorithm   = util_plist:get_value(algorithm, Scheduling),
        AlgoOpts    = util_plist:get_value(options,   Scheduling),
        
        SchedulingRec = #scheduling{algorithm = Algorithm, 
                                    options   = AlgoOpts},
        
        #eredis_pool{ name       = PoolName, 
                      servers    = FormattedServer, 
                      debug      = IfDebugging,
                      scheduling = SchedulingRec}
     end
    ||Pool <-PoolsOptions].

get_env(Par) ->
    application:get_env(smart_eredis, Par).

q(PoolName, Key, Command) ->
    q(PoolName, Key, Command, ?TIMEOUT).
    
q(PoolName, Key, Command, Timeout) ->
    case get_client_by_algo(PoolName, Key) of 
        {ok, Id, Client, DbgClient} ->
            dbg(DbgClient, Id, Key, Timeout),
            eredis:q(Client, Command, Timeout);
        Error->
            Error
    end.

qp(PoolName, Key, Pipeline) ->
    qp(PoolName, Key, Pipeline, ?TIMEOUT).

qp(PoolName, Key, Pipeline, Timeout) ->
    case get_client_by_algo(PoolName, Key) of 
        {ok, Id, Client, DbgClient} ->
            dbg(DbgClient, Id, Key, Timeout),
            eredis:qp(Client, Pipeline, Timeout);
        Error->
            Error
    end.
    

q_noreply(PoolName, Key, Command) ->
    case get_client_by_algo(PoolName, Key) of 
        {ok,Id, Client, DbgClient} ->
            dbg(DbgClient, Id, Key, ?TIMEOUT),
            eredis:q_noreply(Client, Command);
        Error->
            Error
    end.

dbg(undefined, _Id, _Key, _Timeout) -> ok;
dbg(Client,     Id,  Key,  _Timeout) ->
    CMD_COUNTER = ["HINCRBY", Key, Id, 1],
    CMD_TIME    = ["HSET", Key, "time", util_time:string_now()],
    eredis:q_noreply(Client, CMD_COUNTER),
    eredis:q_noreply(Client, CMD_TIME).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Helper Func
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_client_by_algo(PoolName, Key) ->
    case get_pool(PoolName) of 
        {ok, Pool}->
            #eredis_pool{ debug      = IfDebugging, 
                          scheduling = #scheduling{ algorithm = Algorithm, 
                                                    options   = Options}
                          } = Pool,
            get_client_by_algo(PoolName, Key, Algorithm, Options, IfDebugging);
        ErrorFindPool->
            ErrorFindPool
    end.

get_client_by_algo(_PoolName, _Key, ketama, _Options, _IfDebugging) ->
    {error, algorithm_not_implament};
get_client_by_algo(PoolName, _Key, random, Options, IfDebugging) ->
    Ids = util_plist:get_value(ids, Options, []),
    Len = length(Ids),
    case Len > 0 of
        true ->
            random:seed(os:timestamp()),
            Id = random:uniform(Len),
            case get_client(PoolName, Id) of 
                {ok, Client} ->
                    case IfDebugging of
                        false->
                            {ok, Id, Client, undefined};
                        true->
                            case get_client(PoolName, debug) of 
                                 {ok, DbgClient} ->
                                    {ok, Id, Client, DbgClient};
                                 _->
                                    {ok, Id, Client, undefined}
                            end
                    end;
                _->
                    {error, no_available_client}
            end;
        false ->
            {error, no_random_ids}
    end;
get_client_by_algo(_PoolName, _Key,undefined, _Options, _IfDebugging) ->
    {error ,unknown_scheduling_algorithm}.
