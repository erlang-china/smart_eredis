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

-module(smart_eredis).

-include("smart_eredis.hrl").

-include_lib("mini_pool/include/mini_pool.hrl").
-include_lib("ketama/include/ketama.hrl").

-behaviour(gen_server2).

-export([start_link/0]).

-export([start/0, stop/0]).

-export([init/1, 
         handle_call/3, 
         handle_cast/2, 
         handle_info/2, 
         terminate/2, 
         code_change/3]).

-export([all_clients/1, get_client/2]).

-export([all_pools/0, get_pool/1]).

-export([start_pool/1, stop_pool/1]).

%%eredis proxy
-export([q/3, q/4, qp/2, qp/3, qp2/3, qp2/4, q_noreply/3]).

-export([enable_debug/2]).

-define(SERVER, ?MODULE).

%% eredis timeout
-define(TIMEOUT, 5000).

-record(state, {}).

start_link() ->
    gen_server2:start_link({local, ?SERVER}, ?MODULE, [], []).

start() ->
    ensure_started(ets_mgr),
    ensure_started(mini_pool),
    ensure_started(ketama),
    application:start(?MODULE).

stop() ->
    application:stop(?MODULE).

start_pool(Pool) when is_record(Pool, smart_eredis) ->
    gen_server:call(?MODULE,{start_pool, Pool}).

stop_pool(PoolName) when is_atom(PoolName)->
    gen_server:call(?MODULE,{stop_pool, PoolName}).

enable_debug(PoolName, Enable) when is_atom(PoolName), is_atom(Enable)->
    gen_server:call(?MODULE,{enable_debug, PoolName, Enable}).

all_pools()->
    ets:match_object(?TAB_CONFIG, '$1').

get_pool(PoolName) ->
    case ets:lookup(?TAB_CONFIG, PoolName) of 
        [Object]->
            {ok, Object};
        _->
            {error, pool_not_found}
    end.

all_clients(PoolName) ->
    mini_pool:get_pool(PoolName).

get_client(PoolName, Id) ->
    mini_pool:get_pool(PoolName, Id).

%% @private
init([]) ->
    case init_envs() of 
        ok->
            init_config_table(),
            Models = get_pools_models(),
            true  = ets:insert(?TAB_CONFIG, Models),
            [
                begin
                    #smart_eredis{name = Name,servers = StartOpt} = Model,
                    mini_pool:start_pool(#pool_option{ name      = Name,
                                                       component =component_eredis_pool, 
                                                       start_opt = StartOpt})
                end
            || Model<-Models];
        {error, Reason} ->
            error_logger:error_msg("load config error:~n~p~n", [Reason])
    end,
    {ok, #state{}}.

handle_call({start_pool, #smart_eredis{ name    = Name, 
                                        servers = StartOpt} = Pool}, 
                                        _From, State)->
    PoolOpt = #pool_option{ name      = Name, 
                            component = component_eredis_pool,
                            start_opt = StartOpt},
    Reply   = 
    case mini_pool:start_pool(PoolOpt) of
        {ok, Pid} ->
            true = ets:insert(?TAB_CONFIG, Pool),
            {ok, Pid};
        Error ->
            Error
    end,
    {reply, Reply, State};
handle_call({stop_pool, PoolName}, _From, State) ->
    Reply = 
    case mini_pool:stop_pool(PoolName) of
        ok ->
            ets:delete(?TAB_CONFIG, PoolName),
            ok;
        Error ->
            Error
    end,
    {reply, Reply, State};
handle_call({enable_debug, PoolName, Enable}, _From, State) ->
    Reply = internal_enable_debug(PoolName, Enable),
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
                                         {keypos, #smart_eredis.name},
                                         {write_concurrency, false}, 
                                         {read_concurrency,  true}]),
    ok.

get_pools_models() ->
    {ok, PoolsOptions}  = get_env(pools),
    [begin
        {Name, Servers, Scheduling, Options} = Pool,
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
          IfDebugging  = util_plist:get_value(debug, Options, false),
          ModAlgorithm = util_plist:get_value(algorithm, Scheduling),
          InitAlgoOpts = util_plist:get_value(init_options, Scheduling, []),
          RTAlgoOpts   = util_plist:get_value(runtime_options, Scheduling, []),

          IfDebugging  = 
          case IfDebugging of 
              true ->
                case  [Server ||Server <- Servers, 
                            util_plist:get_value(id, Server) == debug] of 
                     [] ->
                        false;
                     _->
                        true
                end;
              false ->
                false
          end,

          ok = util_misc:check_callback(smart_eredis_algorithm, ModAlgorithm),
          SchedulingRec = 
             #scheduling{ get_client_id   = fun ModAlgorithm:get_client_id/3, 
                          runtime_options = RTAlgoOpts},

          ok = ModAlgorithm:init(Name, InitAlgoOpts),
          #smart_eredis{ name       = Name, 
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

qp(PoolName, Pipeline) ->
    qp2(PoolName, undefined, Pipeline, ?TIMEOUT).

qp(PoolName, Pipeline, Timeout) ->
    qp2(PoolName, undefined, Pipeline, Timeout).

qp2(PoolName, HashKey, Pipeline) ->
    qp2(PoolName, HashKey, Pipeline, ?TIMEOUT).

qp2(PoolName, HashKey, Pipeline, Timeout) ->
    {Normal, Exception} = group_pipeline(PoolName, Pipeline, HashKey),
    RedisRet =
    [ begin
        {Orders, CmdLines} = lists:unzip(Lines),
        {ok, Client} = get_client(PoolName, Id),
        lists:zip(Orders, eredis:qp(Client, CmdLines, Timeout))
       end
    || {Id, Lines} <- Normal], 
    CombinedRet = orddict:from_list(lists:flatten(RedisRet ++ Exception)),
    [Ret||{_Id, Ret}<-CombinedRet].

q_noreply(PoolName, Key, Command) ->
    case get_client_by_algo(PoolName, Key) of 
        {ok, Id, Client, DbgClient} ->
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
%% Helper Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_client_by_algo(PoolName, Key) ->
    case get_pool(PoolName) of 
        {ok, Pool}->
            #smart_eredis{ debug      = IfDebugging, 
                           scheduling = #scheduling{get_client_id   = GetClient, 
                                                    runtime_options = Options}
                          } = Pool,
            case GetClient(PoolName, Key, Options) of 
                {ok, Id} ->
                    get_client_with_dbg(PoolName, Id, IfDebugging);
                ErrorGetClientId ->
                    ErrorGetClientId
            end;
        ErrorFindPool->
            ErrorFindPool
    end.

internal_enable_debug(PoolName, Enable) ->
    case get_pool(PoolName) of 
        {ok, #smart_eredis{ debug   = EnabledState, 
                            servers = Servers} = Pool} ->
            case EnabledState of 
                Enable ->
                    {error, nothing_changed};
                _->
                    case [Server ||#redis{id = Id} =Server <- Servers, 
                            Id == debug] of 
                        [] ->
                            {error, no_debug_redis_server};
                        [DebugServer] ->
                            true = ets:insert(?TAB_CONFIG, 
                                      Pool#smart_eredis{debug = Enable}),
                            {ok, DebugServer}
                    end
            end;
        Error ->
            Error
    end.

get_client_with_dbg(PoolName, Id, IfDebugging) ->
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
    end.

get_key(Key, undefined)-> Key;
get_key(_Key, HashKey)-> HashKey.

group_pipeline(PoolName, Pipeline, HashKey) -> 
    FlattenDatas = group_pipeline_0(PoolName, Pipeline, HashKey, 1, []),
    group_pipeline_1(FlattenDatas, orddict:new(), []).

group_pipeline_0(_PoolName, [], _HashKey, _OrderId, Accout) -> lists:reverse(Accout);
group_pipeline_0(PoolName, [[_Command, Key|_T] = Oneline|Pipeline], HashKey, OrderId, Accout) -> 
    Ret = 
    case ketama:get_object(PoolName, get_key(Key, HashKey)) of 
             {ok, {Id, _Obj}} ->
                {ok, {Id, {OrderId, Oneline}}};
             {error, Reason} ->
                {error, {OrderId, {error, Reason}}}
    end,
    group_pipeline_0(PoolName, Pipeline, HashKey, OrderId+1, [Ret|Accout]).

group_pipeline_1([], NormalDict, ErrorList) -> 
    {NormalDict, ErrorList};
group_pipeline_1([{ok,{Id, Oneline}}|T], NormalDict, ErrorList)->
    NormalDict0 =
    case orddict:is_key(Id, NormalDict) of
         true ->
            orddict:append(Id, Oneline, NormalDict);
         false ->
            orddict:store(Id, [Oneline], NormalDict)
    end,
    group_pipeline_1(T, NormalDict0, ErrorList);
group_pipeline_1([{error, Oneline}|T], NormalDict, ErrorList)->
    group_pipeline_1(T, NormalDict, [Oneline|ErrorList]).