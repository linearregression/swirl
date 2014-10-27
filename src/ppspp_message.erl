%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

%% @doc Library for PPSPP over UDP, aka Swift protocol
%% <p>This module implements a library of functions necessary to
%% handle the wire-protocol of PPSPP over UDP, including
%% functions for encoding and decoding messages.</p>
%% @end

-module(ppspp_message).
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-spec test() -> term().
-endif.

%% api
-export([unpack/2,
         pack/1,
         get_message_type/1,
         handle/3]).

-opaque messages() :: list(message()).
-opaque message() :: {message_type(), any()}.
-opaque message_type() :: handshake
| data
| ack
| have
| integrity
| pex_resv4
| pex_req
| signed_integrity
| request
| cancel
| choke
| unchoke
| pex_resv6
| pex_rescert.

-export_type([messages/0,
              message/0,
              message_type/0]).

%% api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc unpack a datagram segment into a PPSPP message using erlang term format
%% <p>  Deconstruct PPSPP UDP datagram into multiple erlang terms, including
%% parsing any additional data within the same segment. Any parsing failure
%% is fatal & will propagate back to the attempted datagram unpacking.
%% <ul>
%% <li>Message type</li>
%% <li>orddict for Options</li>
%% <ul>
%% </p>
%% @end

-spec unpack(binary(), ppspp_options:options()) -> message() | messages().

unpack(Maybe_Messages, Swarm_Options) when is_binary(Maybe_Messages) ->
    unpack3(Maybe_Messages, [], Swarm_Options).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec pack(messages()) -> {ok, iolist()}.
pack(Messages) -> {ok, pack(Messages, [])}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% private

-spec pack(messages(), iolist()) -> iolist().
%% Try to pack another valid message, peeling off and parsing
%% recursively the remainder, accumulating valid (packed) messages.
%% A failure anywhere in a message ultimately causes the entire iolist
%% to be rejected.
pack([Message, Rest], Messages_as_iolist) ->
    pack(Rest, [pack_message(Message) | Messages_as_iolist]);
%% if head binary is empty, all messages were packed successfully
pack([], Messages_as_iolist) -> lists:reverse(Messages_as_iolist).

-spec pack_message(message()) -> binary().
pack_message(_Message) -> <<>>.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %% if the binary is empty, all messages were parsed successfully
-spec unpack3(binary(), message() | messages(), ppspp_options:options()) ->
    messages() | { message(), binary()}.
unpack3( <<>>, Parsed_Messages, _) ->
    lists:reverse(Parsed_Messages);
%% otherwise try to unpack another valid message, peeling off and parsing
%% recursively the remainder, accumulating valid (parsed) messages.
%% A failure anywhere in a message ultimately causes the entire datagram
%% to be rejected.
unpack3(<<Maybe_Message_Type:?PPSPP_MESSAGE_SIZE, Rest/binary>>,
        Parsed_Messages, Swarm_Options) ->
    Type = get_message_type(Maybe_Message_Type),
    {Parsed_Message, Maybe_More_Messages} = route_to(Type, Rest, Swarm_Options),
    unpack3(Maybe_More_Messages,
            [Parsed_Message | Parsed_Messages],
            Swarm_Options).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% route to specific parser per message type, with swarm options if required
-spec route_to(message_type(), binary(), ppspp_options:options()) -> 
    {message(), binary()} | {error, atom()}.
route_to(handshake, Binary, _) ->
    {Handshake, Maybe_Messages} =  ppspp_handshake:unpack(Binary),
    {Handshake, Maybe_Messages};
route_to(have, Binary, Swarm_Options) ->
    Chunk_Method = ppspp_options:get_chunk_addressing_method(Swarm_Options),
    {Have, Maybe_Messages} =  ppspp_have:unpack(Chunk_Method, Binary),
    {Have, Maybe_Messages};
route_to(_, _, _) ->
    {error, unsupported_ppspp_message_type}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec get_message_type(non_neg_integer()) -> message_type().
get_message_type(Maybe_Message_Type)
  when is_integer(Maybe_Message_Type),
       Maybe_Message_Type < ?PPSPP_MAXIMUM_MESSAGE_TYPE ->
    %% message types in the current spec version
    Message_Type = case <<Maybe_Message_Type:?PPSPP_MESSAGE_SIZE>> of
                       ?HANDSHAKE -> handshake;
                       ?DATA -> data;
                       ?ACK -> ack;
                       ?HAVE -> have;
                       ?INTEGRITY -> integrity;
                       ?PEX_RESv4 -> pex_resv4;
                       ?PEX_REQ -> pex_req;
                       ?SIGNED_INTEGRITY -> signed_integrity;
                       ?REQUEST -> request;
                       ?CANCEL -> cancel;
                       ?CHOKE -> choke;
                       ?UNCHOKE -> unchoke;
                       ?PEX_RESv6 -> pex_resv6;
                       ?PEX_REScert -> pex_rescert
                   end,
    ?DEBUG("message: parser got valid message type ~p~n", [Message_Type]),
    Message_Type.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%-spec ... handle takes a tuple of {type, message_body} where body is a
%%    parsed orddict message and returns either
%%    {error, something} or tagged tuple for the unpacked message
%%    {ok, reply} where reply is probably an orddict to be sent to the
%%    alternate peer.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HANDLE MESSAGES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The payload of the HANDSHAKE message is a channel ID (see
%  Section 3.11) and a sequence of protocol options.  Example options
%  are the content integrity protection scheme used and an option to
%  specify the swarm identifier.  The complete set of protocol options
%  are specified in Section 7.

%-spec handle(message()) -> {ok, any()}.

%handle({handshake, Body}) -> ppspp_handshake:handle(Body);

%handle(Message) ->
%?DEBUG("message: handler not yet implemented ~p~n", [Message]),
%{ok, ppspp_message_handler_not_yet_implemented}.

%%-----------------------------------------------------------------------------
%% HANDSHAKE    TESTED.
%% The payload of the HANDSHAKE message is a channel ID (see Section 3.11) and
%% a sequence of protocol options.  Example options are the content integrity
%% protection scheme used and an option to specify the swarm identifier.  The
%% complete set of protocol options are specified in Section 7.
handle({Type, seeder}, {handshake, Payload}, State) ->
    {ok, HANDSHAKE} = prepare(Type, {handshake, Payload}, State),
    {ok, HAVE}      = prepare(Type, {have, orddict:new()}, State),
    {ok, [HANDSHAKE | HAVE]};

handle({_Type, leecher}, {handshake,_Payload},_State) ->
    %% leecher will set any undefined options in State using HANDSHAKE.
    %% Currently all the options are pre-set in the init function, so if we
    %% need to use the handshake options recevied only then we need to
    %% implement this.
    {ok, []};

%%------------------------------------------------------------------------------
%% ACK : Update peer_state in State.
handle(_Type_Role, {ack, Payload}, State) ->
    Bin            = peer_core:fetch(range, Payload),
    Peer_State     = State#peer.peer_state,
    New_Ack_Range  = peer_core:update_ack_range(Bin, Peer_State),
    New_Peer_State = orddict:store(ack_range, New_Ack_Range, Peer_State),
    {ok, State#peer{peer_state=New_Peer_State}};

%%------------------------------------------------------------------------------
%% HAVE     TESTED
handle({static, leecher}, {have, _Payload},_State) ->
    %% TODO : discuss how to request RANGE
    ok;

handle({live, leecher}, {have, Payload}, #peer{state=tune_in} = State) ->
    %% HAVE in live stream is piggybacked to figure out latest munro hash.
    %% TODO discuss if address of peers sending highest munro needs to be
    %% stored.
    Latest_Munro  = peer_core:fetch(range, Payload),
    %% update the munro if latest munro is greater than the current one.
    Server_Data   = peer_core:piggyback(have, {State, Latest_Munro}),
    case peer_core:is_stable(Server_Data) of
        true  ->
            New_Server_Data = orddict:erase(stable_munro, Server_Data),
            %% prepare request message for the highest munro
            {ok, REQUEST} = prepare(live,
                                    {request,
                                     orddict:fetch(latest_munro, Server_Data)},
                                    State),
            {ok, State#peer{state=streaming, server_data=New_Server_Data},
             REQUEST};
        false ->
            Counter         = orddict:fetch(stable_munro, Server_Data)-1,
            New_Server_Data = orddict:store(stable_munro, Counter, Server_Data),
            {ok, State#peer{server_data=New_Server_Data}}
    end;

%% TODO confirm if the expression : #peer{state=streaming} =_State will work !
%% In case leecher is already in the streaming state any new HAVE will
%% correspond to new data injected into the swarm
handle({live, leecher}, {have, Payload}, #peer{state=streaming} = State) ->
    New_Munro     = peer_core:fetch(range, Payload),
    {ok, REQUEST} = prepare(live, {request, New_Munro}, State),
    {ok, State, REQUEST};

%%------------------------------------------------------------------------------
%% INTEGRITY    TESTED
%% TODO figure out how to handle integrity messages. The leecher will recevive
%% integrity message which can span multiple chunks so we need to piggybank
%% integrity messages untill the right DATA packet arrives DOUBT : how will
%% that for which data packet are the integrity messages ment for !!!
handle({static, leecher}, {integrity, _Payload},_State) ->
    ok;

handle({live, leecher}, {integrity, Payload}, State) ->
    Bin            = peer_core:fetch(range, Payload),
    Hash           = peer_core:fetch(hash, Payload),
    New_Peer_State = peer_core:piggyback(integrity, {State, Bin, Hash}),
    {ok, State#peer{peer_state = New_Peer_State}};

%%------------------------------------------------------------------------------
%% SIGNED_INTEGRITY
handle({live, leecher}, {signed_integrity, Payload}, State) ->
    %% TODO reject SIGNED_INTEGRITY if ntp time is too late.
    Munro_Root      = peer_core:fetch(range, Payload),
    Peer_State      = State#peer.peer_state,
    {_, Munro_Hash} = lists:keyfind(Munro_Root, 1, orddict:find(integrity,
                                                                Peer_State)),
    Signature       = peer_core:fetch(signature, Payload),
    Public_Key      = (State#peer.options)#options.ppspp_swarm_id,

    %% verify signature of the munro hash. we use none becoz Munro is sha hash.
    true = public_key:verify(Munro_Hash, none, Signature, Public_Key),
    %% NOTE : leecher stores Signature to help other peers in secure tune_in.
    mtree_store:insert(State#peer.mtree, {Munro_Root, Munro_Hash, Signature}),
    %% remove the Munro_Root from integrity.
    New_Integrity  = lists:keydelete(Munro_Root, 1, orddict:fetch(integrity,
                                                                  Peer_State)),
    New_Peer_State = orddict:store(integrity, New_Integrity, Peer_State),
    {ok, State#peer{peer_state = New_Peer_State}};

%%------------------------------------------------------------------------------
%% REQUEST      TESTED
handle({static, _}, {request, [_Start, _End]},_State) ->
    %% TODO implement static code.
    %handle_REQ_List({static, State}, REQ_List, []);
    ok;

handle({live, _}, {request, Payload}, State) ->
    [Start, End]  = mtree_core:bin_to_range(peer_core:fetch(range, Payload)),
    Start_Munro   = mtree_core:get_munro_root(Start),
    End_Munro     = mtree_core:get_munro_root(End),
    %% prepare list of requested chunk IDs with their corresponding Munro_Root.
    {ok, Request_List} = peer_core:get_bin_list({Start_Munro, End_Munro},
                                                {Start, End}, []),
    %% Request_List: [Munro_Root1, bins ... , Munro_Root2, bins ..]
    %% the bins that follow the Munro_Root lie in the range of the Munro_Root.
    {ok, process_request({live, State}, Request_List, [])};

handle(_Type_Role, Message,_State) ->
    ?DEBUG("message: handler not yet implemented ~p~n", [Message]),
    {ok, ppspp_message_handler_not_yet_implemented}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PREPARE MESSAGES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% STATUS : tested.
%% HANDSHAKE message is of the sort :
%% {handshake, [{channel, [{source, Channel_Id}, {destination, Channel_Id}]},
%%              {options, [{}, {}, ...]}]
prepare(Type, {handshake, Payload}, State) ->
    {source, Channel_Id} = lists:keyfind(source, 1, orddict:fetch(channel,
                                                                  Payload)),
    Sub_Options =
    [ {ppspp_swarm_id, (State#peer.options)#options.ppspp_swarm_id},
      {ppspp_version,  (State#peer.options)#options.ppspp_version},
      {ppspp_minimum_version,
       (State#peer.options)#options.ppspp_minimum_version},
      {ppspp_chunking_method,
       (State#peer.options)#options.ppspp_chunking_method},
      {ppspp_integrity_check_method,
       (State#peer.options)#options.ppspp_integrity_check_method},
      {ppspp_merkle_hash_function,
       (State#peer.options)#options.ppspp_merkle_hash_function}],

    %% Add LIVE streaming options incase the seeder is in live stream swarm.
    Options =
    if
        Type =:= live orelse Type =:= injector ->
            [{ppspp_live_signature_algorithm,
              (State#peer.options)#options.ppspp_live_signature_algorithm},
             {ppspp_live_disard_window,
              (State#peer.options)#options.ppspp_live_discard_window} |
             Sub_Options];
        true -> Sub_Options
    end,

    %% TODO : allocate free channel & store it in Payload as source channel id
    Channel  = [{source, not_implemented}, {destination, Channel_Id}],
    {ok, {handshake, orddict:from_list([{channel, Channel},
                                        {options, Options}])}};

%%------------------------------------------------------------------------------
%% ACK : {ack, [{range, Bin}]
prepare(_Type, {ack, Bin}, _State) ->
    {ok, {ack, orddict:from_list([{range, Bin}])}};

%%------------------------------------------------------------------------------
%% HAVE : {have, [{range, Bin}]}
prepare(static, {have,_Payload}, State) ->
    Peaks = mtree:get_peak_hash(State#peer.mtree),
    Have  = [{have, orddict:from_list([{range, Bin}])} || {Bin, _} <- Peaks],
    {ok, Have};
prepare(_Live,  {have,_Payload}, State) ->
    %% HAVE in case of live stream only sends the latest munro
    {ok, Munro_Root, _} = mtree:get_latest_munro(State#peer.mtree),
    {ok, [{have, orddict:from_list([{range, Munro_Root}])}]};

%%------------------------------------------------------------------------------
%% REQUEST : {request, [{range, Bin}]}
prepare(_Type, {request, Bin}, _State) ->
    {ok, {request, orddict:from_list([{range, Bin}])}};

%%------------------------------------------------------------------------------
%% DATA : {data, [{range, Bin}, {timestamp, int}, {data, binary}]}
prepare(_Type, {data, Chunk_ID}, State) ->
    {ok, _Hash, Data} = mtree_store:lookup(State#peer.mtree, Chunk_ID),
    %% TODO : add ntp module and filter out the timestamp.
    Ntp_Timestamp = peer_core:time(), %% not implemented yet !
    {ok, {data, orddict:from_list([{range, Chunk_ID},
                                   {timestamp, Ntp_Timestamp},
                                   {data, Data}])}};

%%------------------------------------------------------------------------------
%% INTEGRITY : {integrity, [{range, Bin}, {hash, binary}]
prepare(_Type, {integrity, Bin}, State) ->
    {ok, Hash, _Data} = mtree_store:lookup(State#peer.mtree, Bin),
    %% CAUTION : the range is set to a bin
    {ok, {integrity, orddict:from_list([{range, Bin}, {hash, Hash}])}};
prepare(_Type, {integrity, Bin, Hash}, _State) ->
    {ok, {integrity, orddict:from_list([{range, Bin}, {hash, Hash}])}};

%%------------------------------------------------------------------------------
%% SIGNED_INTEGRITY : {signed_integrity, [{range, Bin},
%%                                        {timestamp, Time},
%%                                        {signature, binary}]
%% NOTE : Bin MUST be either leaf or munro 
prepare(live, {signed_integrity, Leaf}, State) when Leaf rem 2 =:= 0 ->
    Munro_Root    = mtree_core:get_munro_root(Leaf),
    %% TODO : add ntp module and filter out the timestamp.
    Ntp_Timestamp         = peer_core:time(), %% not implemented yet !
    {ok, _Hash, Signture} = mtree_store:lookup(State#peer.mtree, Munro_Root),
    {ok, {data, orddict:from_list([{range, Munro_Root},
                                   {timestamp, Ntp_Timestamp},
                                   {signature, Signture}])}};
%% CAUTION only Munro_Root should be sent here !
prepare(live, {signed_integrity, Munro_Root}, State) ->
    Ntp_Timestamp         = peer_core:time(), %% not implemented yet !
    {ok, _Hash, Signture} = mtree_store:lookup(State#peer.mtree, Munro_Root),
    {ok, {signed_integrity, orddict:from_list([{range, Munro_Root},
                                               {timestamp, Ntp_Timestamp},
                                               {signature, Signture}])}}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% LOCAL INTERNAL FUNCTIONs
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc process_request/3 : REQ_List and return value will be as follows
%% REQ_List (live): [Munro_Root1, Leaf_bin ... , Munro_Root2, Leaf_bins ..]
%% Returns (live) : [INTEGRITY, SIGNED_INTEGRITY, INTEGRITY, DATA, ..] messages
%% REQ_List (static) : [Leaf_bin, ...]
%% Returns (static)  : [INTEGRITY, DATA, INTEGRITY, DATA, ...] messages
%% @end 
process_request(_, [], Acc) ->
    lists:reverse(Acc);
process_request({Type, State}, [Leaf | Rest], Acc) when Leaf rem 2 =:= 0 ->
    %% get the uncles based on the previous ACKs
    Uncle_Hashes = peer_core:fetch_uncles(Type, State, Leaf),
    INTEGRITY    =
    lists:reverse(lists:map(
                    fun({Uncle, Hash}) ->
                            {ok, Integrity} = prepare(live, {integrity, Uncle, Hash}, State),
                            Integrity
                    end, Uncle_Hashes)),
    {ok, DATA}     = prepare(live, {data, Leaf}, State),
    Response       = lists:flatten([DATA,INTEGRITY | Acc]),
    New_Peer_State = orddict:append(req_range, Leaf, State#peer.peer_state),
    New_State      = State#peer{peer_state=New_Peer_State},
    process_request({live, New_State}, Rest, Response);
process_request({live, State}, [Munro_Root | Rest], Acc) ->
    {ok, INTEGRITY}        = prepare(live, {integrity, Munro_Root}, State),
    {ok, SIGNED_INTEGRITY} = prepare(live, {signed_integrity,Munro_Root},State),
    process_request({live, State}, Rest, [SIGNED_INTEGRITY, INTEGRITY | Acc]).
