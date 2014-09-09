%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy
%% of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations
%% under the License.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc the module contains the funcitons for the leecher and seeder.
%% @end
-module(peer_core).

-include("../include/ppspp_records.hrl").

-export([init_server/2,
         update_state/3,
         get_peer_state/2,
         piggyback/2,
         update_ack_range/2,
         get_bin_list/3,
         fetch_uncles/3,
         is_stable/1,
         fetch/2,
         time/0]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Initialize the gen_server.
%% @end
init_server(static, {Swarm_ID, State_Table}) ->
    State = #peer{},
    New_State =
    State#peer{
       type         = static,
       state        = normal,
       server_data  = orddict:new(),
       peer_table   = State_Table,
       mtree        = Swarm_ID,
       options      =
       (State#peer.options)#options{
          ppspp_swarm_id               = Swarm_ID, 
          ppspp_integrity_check_method = ?PPSPP_DEFAULT_INTEGRITY_CHECK_METHOD
         }
      },
    {ok, New_State};

%% remaining types are live and injector. swarm options will remain same
init_server(Type, {Swarm_ID, State_Table}) ->
    State = #peer{},
    New_State =
    State#peer{
       type         = Type,
       state        = tune_in,
       server_data  = orddict:new(),
       peer_table   = State_Table,
       mtree        = Swarm_ID,
       options      =
       (State#peer.options)#options{
          ppspp_swarm_id               = Swarm_ID, 
          ppspp_live_discard_window    = ?PPSPP_DEFAULT_LIVE_DISCARD_WINDOW,
          ppspp_integrity_check_method =
          ?PPSPP_DEFAULT_LIVE_INTEGRITY_CHECK_METHOD,
          ppspp_live_signature_algorithm =
          ?PPSPP_DEFAULT_LIVE_SIGNATURE_ALGORITHM
         }
    },
    {ok, New_State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc update the State variable on the arrival of packets from different
%% peers
%% @end
update_state(Server_Type, Msg, State) ->
    %% TODO get the state of peer from ETS table and store it in State.
    %% peer_state in ETS table will be of the form : {Peer_Name, Peer_State}
    %% Where Peer_Name : {Peer_adderss, seeder/leecher}.
    %% Peer_State : incase the peer is seeder then Peer_State will be orddict
    %% containing "range" of chunks ACKed and 
    %% incase peer is leecher orddict will contain "range" received by the
    %% leecher from that peer and "integrity" messages recevied from that peer
    %%
    %% NOTE : if peer lookup fails then add the peer to the table with the new
    %% dict as follows :
    %% for leecher :
    %%   orddict:from_list([{range, []},
    %%                      {integrity,
    %%                      orddict:from_list([{bin, hash}, {bin, hash} ..])}])
    %% for seeder:
    %%   orddict:from_list([{range, []}])
    %%
    %% State#peer.peer_state will contain ACKed Chunk_IDs
    %% TODO add channel ID to the Peer and Peer_State.
    %% TODO find out the correct way the peer address is sotred in the decoded
    %% message
    %% Address = "127.0.0.1:54181"
    {endpoint, Address} = lists:keyfind(endpoint, orddict:find(peer, Msg)),
    %%
    Peer_State = get_peer_state(State#peer.peer_table, {Address, Server_Type}),
    New_State  = State#peer{peer={Address, Server_Type},peer_state=Peer_State},
    {ok, New_State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc get_peer_state/2 : get the state of the peer from the peer_table and if
%% not present then initilize empty state and return that.
%% @end
get_peer_state(Table, Peer) ->
    case peer_store:lookup(Table, Peer) of
        {error, _}  ->
            peer_store:insert_new(Table, Peer),
            get_peer_state(Table, Peer);
        {ok, State} -> State
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc get_peer_state/2 : get the state of the peer from the peer_table and if
%% not present then initilize empty state and return that.
%% @end
piggyback(have, {State, Latest_Munro}) ->
    Server_Data = State#peer.server_data,
    Peer        = State#peer.peer,
    case orddict:find(latest_munro, Server_Data) of
        %% add "have" Payload if not present
        error   ->
            New_Data = orddict:store(latest_munro, Latest_Munro, Server_Data),
            orddict:store(munro_peers, [Peer], New_Data);
        %% if Latest munro is more recent then overite the previous munro
        {ok, Munro} when Latest_Munro > Munro ->
            New_Data = orddict:store(latest_munro, Latest_Munro, Server_Data),
            orddict:store(munro_peers, [Peer], New_Data);
        %% store the peers with the latest munro.
        {ok, Munro} when Latest_Munro =:= Munro ->
            orddict:append(munro_peers, Peer, Server_Data);
        _ ->
            Server_Data
    end;

piggyback(integrity, {State, Bin, Hash}) ->
    Peer_State = State#peer.peer_state,
    orddict:append(integrity, {Bin, Hash}, Peer_State).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc when new bin is received in ACK, we get the previously ACKed bins from
%% State and filter those bins that don't lie in the range of this Bin so as to
%% get list of bins that correspond to the range that has been acked by the
%% peer.
%% @end
update_ack_range(New_Bin, Peer_State) ->
    Bin_Range = mtree_core:bin_to_range(New_Bin),
    case orddict:find(ack_range, Peer_State) of
        error       ->
            [New_Bin];
        {ok, Ack_Range} ->
            lists:filter( fun(Bin) ->
                                  not mtree_core:lies_in(Bin, Bin_Range)
                          end, Ack_Range)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc return list of bins to request for live stream :
%% [Munro_Root1, bins ... , Munro_Root2, bins ..]
%% the bins that follow the Munro_Root lie in the range of the Munro_Root.
%% @end
get_bin_list({End_Munro, End_Munro}, {Start, End}, Acc) ->
    {ok, lists:concat([Acc, [End_Munro | lists:seq(Start, End, 2)]])};
get_bin_list({Start_Munro, End_Munro}, {Start, End}, Acc) ->
    [_, Last] = mtree_core:bin_to_range(Start_Munro),
    New_Acc   = lists:concat([Acc, [Start_Munro | lists:seq(Start, Last, 2)]]),
    {ok, Munro_Root} = mtree_core:get_next_munro(Start_Munro),
    get_bin_list({Munro_Root, End_Munro}, {Last+2, End}, New_Acc).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc fetch_uncles/3 : gets the required uncles for live & static stream
%% check if the previous Leaf (ie Leaf -2) has been ACKed, if not then get
%% all the uncles corresponding to the current leaf.
%% @end
fetch_uncles(Type, State, Leaf) ->
    Ack_Range = case orddict:find(ack_range, State#peer.peer_state) of
                    error -> [];
                    {ok, Ack_List} -> Ack_List
                end,
    Req_Range = case orddict:find(req_range, State#peer.peer_state) of
                    error -> [];
                    {ok, Req_List} -> Req_List
                end,
    fetch_uncles(Type, State#peer.mtree,
                 lists:merge([Ack_Range, Req_Range]), Leaf).

fetch_uncles(static, MTree, [], Leaf) ->
    mtree:get_all_uncle_hashes(MTree, Leaf);
fetch_uncles(static, MTree, List, Leaf) ->
    case in_bin_list(Leaf-2, List) of
        true  ->
            mtree:get_all_uncle_hashes(MTree, Leaf);
        false ->
            mtree:get_uncle_hashes(MTree, Leaf)
    end;

fetch_uncles(live, MTree, [], Leaf) ->
    mtree:get_all_munro_uncles(MTree, Leaf);
fetch_uncles(live, MTree, List, Leaf) ->
    case in_bin_list(Leaf-2, List) of
        true  ->
            mtree:get_munro_uncles(MTree, Leaf);
        false ->
            mtree:get_all_munro_uncles(MTree, Leaf)
    end.

%% check if the leaf lies in the Bin list.
in_bin_list(Leaf, _Ack_List) when Leaf =< 0 ->
    false;
in_bin_list(_Leaf, []) ->
    false;
in_bin_list(Leaf, [Bin | Rest]) ->
    case mtree_core:lies_in(Leaf, mtree_core:bin_to_range(Bin)) of
        true  -> true;
        false -> in_bin_list(Leaf, Rest)
    end.

%% checks if the stable munro is 0 or not
is_stable(Server_Data) ->
    case orddict:fetch(stable_munro, Server_Data)-1 of
        Counter when Counter =< 0 -> true;
        _ -> false
    end.

%% fetches keys from orddict
fetch(Field, Payload) ->
    orddict:fetch(Field, Payload).

%% return ntp time
time() ->
    %% TODO : add the ntp module and call ntp:ask()
    peer_core_not_implemented.
