-module(eredis_keeper).

-behaviour(gen_server).

-include("eredis_pool.hrl").

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(RECONNECT_TIME, 200).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/1 ,get_status/1, all_clients/1, get_client/2]).

start_link(Pool) when is_record(Pool, eredis_pool)->
    #eredis_pool{name = PoolName} = Pool,
    gen_server:start_link({local, PoolName}, ?MODULE, [Pool], []).

get_status(PoolName) ->
    gen_server:call(PoolName,{get_status}).

all_clients(PoolName)->
    gen_server:call(PoolName,{all_clients}).

get_client(PoolName, Id)->
    gen_server:call(PoolName,{get_client, Id}).
%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {status = inactive, clients = orddict:new()}).

init([Pool]) when is_record(Pool, eredis_pool)->
    process_flag(trap_exit, true),
    State = 
    case start_pool(Pool) of 
        {ok, Clients}->
            #state{status = actived, clients = Clients};
        _->
            #state{status = inactive}
    end,
    {ok, State}.

handle_call({all_clients}, _From, State)->
    #state{clients = Clients} = State,
    {reply, {ok, Clients}, State};
handle_call({get_client, Id}, _From, State)->
    #state{ clients = Clients} = State,
    Reply = 
    case orddict:find(Id, Clients) of
        {ok, Value} ->
            {ok, Value};
        _->
            {error, not_found}
    end,
    {reply, Reply, State};
handle_call({get_status}, _From, State)->
    {reply, {ok, State}, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({on_eredis_pool_exception,{Pool, Reason}}, State) 
                    when is_record(Pool, eredis_pool) ->
    NewState = State#state{status = inactive, clients = orddict:new()},
    Server = self(),
    spawn_link(fun()->
        try 
            erlang:send_after(?RECONNECT_TIME, Server, {init, Pool})
        catch
            Class:Reason -> {Class, Reason} 
        end
    end),
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({on_eredis_exception, {PoolName, Server, _Reason}}, State) ->
    #state{clients = Clients} = State,
    #redis{id      = ChildId} = Server,
    {ChildId, NewClientPid} = connect_to_server(PoolName, Server),
    NewClients0 = orddict:erase(ChildId, Clients),
    NewClients  = orddict:append(ChildId, NewClientPid, NewClients0),
    {noreply, State#state{clients = NewClients}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================
start_pool(Pool) when is_record(Pool, eredis_pool) ->
    #eredis_pool{name = PoolName, servers = Servers} = Pool,
    Children = [connect_to_server(PoolName, Server) || Server <-Servers],
    {ok, Children}.

connect_to_server(PoolName, Server) when is_record(Server, redis)->
    FunWatchEredis  = get_watch_eredis_fun(),
    #redis{ id       = Id,
            host     = Host, 
            port     = Port,
            database = Db, 
            password = Password} = Server,
    {ok, Pid} = eredis:start_link(Host, Port,  Db, Password),
    watch_eredis(PoolName, Server, self() , Pid, FunWatchEredis),
    gen_server:cast(eredis_pool, {on_eredis_client_update, 
                                  PoolName,
                                  Id, 
                                  Pid}),
    {Id, Pid}.

get_watch_eredis_fun()->
    fun(PName, Svr, SPid, CPid, Rs)->
        on_eredis_exception(PName, Svr, SPid, CPid, Rs)
    end.  

watch_eredis(PoolName, Server, SupPid, ChildPid, Fun) when   
                                                 is_pid(SupPid),
                                                 is_pid(ChildPid)->
     spawn_link(fun() ->
                process_flag(trap_exit, true),
                link(ChildPid),
                receive
                    {'EXIT', ChildPid, Reason} ->
                        case  is_process_alive(SupPid) of 
                            true -> 
                                Fun(PoolName, Server, SupPid, ChildPid, Reason);
                            false->
                                ok
                        end
                end
    end).

on_eredis_exception(PoolName, Server, SupPid, ChildPid, Reason)->
    erlang:send_after(?RECONNECT_TIME, 
                      SupPid, 
                      {on_eredis_exception, 
                      {PoolName, Server, Reason}}),
    error_logger:error_msg("pool_name:~p~nserver:~p~nchild_pid:~p~nreason:~n~p~n",
                            [PoolName, Server, ChildPid, Reason]).