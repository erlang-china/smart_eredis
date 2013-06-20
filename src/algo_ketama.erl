-module(algo_ketama).

-behaviour(smart_eredis_algorithm).

-include("smart_eredis.hrl").
-include_lib("ketama/include/ketama.hrl").

-export([init/2, get_client_id/3]).

init(PoolName, Options)->
    case ketama:is_ring_exist(PoolName) of
        false ->
            PROpts  = util_plist:get_value(ring_opt, Options, []),
            NCopies = util_plist:get_value(node_copies, PROpts, 40),
            Expand  = util_plist:get_value(expand_node, PROpts, true),
            MatchOp = util_plist:get_value(match_operator, PROpts, '>='),
            ConChar = util_plist:get_value(concat_char, PROpts, ":"),
            GenType = util_plist:get_value(copies_gen_type, PROpts, weight),
            RingOpt = 
            #ring_opt{name            = PoolName,
                      node_copies     = NCopies,
                      expand_node     = Expand, 
                      match_operator  = MatchOp,
                      concat_char     = ConChar,
                      copies_gen_type = GenType},
            ketama:add_ring(RingOpt),
            Nodes = util_plist:get_value(nodes, Options),
            [begin 
              Node = 
              #node{ id         = NodeId, 
                     hash_seed  = HashSeed, 
                     copies_num = CopiesNum, 
                     object     = Object},
             ok = ketama:add_node(PoolName, Node)
             end
            || {NodeId, HashSeed, CopiesNum, Object} <-Nodes],
            ok;
        true ->
            ok
    end.

get_client_id(PoolName, Key, _Options)->
    case ketama:get_object(PoolName, Key) of 
        {ok, {_NodeId, Object}} ->
            {ok , Object};
        Error ->
            Error
    end.