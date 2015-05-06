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

%% @doc Library for PPSPP over UDP, aka PPSPP protocol
%% <p>This module implements a library of functions necessary to
%% handle the wire-protocol of PPSPP over UDP, including
%% functions for encoding and decoding datagrams.</p>
%% @end

-module(ppspp_datagram).
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-spec test() -> term().
-endif.

%% api
-export([handle_packet/1,
         handle_datagram/2,
         get_peer_uri/1,
         get_peer_channel/1,
         unpack/3,
         pack/1]).

-opaque endpoint() :: {endpoint, list( endpoint_option())}.
-opaque endpoint_option() :: {ip, inet:ip_address()}
| {socket, inet:socket()}
| {port, inet:port_number()}
| {transport, udp}
| {uri, string()}
| ppspp_channel:channel().
-opaque datagram() :: {datagram, list(endpoint() | ppspp_message:messages())}.
-export_type([endpoint/0,
              endpoint_option/0,
              datagram/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc  helper functions
%% @end
-spec peer_to_string(inet:ip_address(), inet:port_number()) -> string().

peer_to_string(Peer, Port) ->
    lists:flatten([[inet_parse:ntoa(Peer)], $:, integer_to_list(Port)]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc translates raw udp packet into a tidy structure for later use
%% @end

-spec build_endpoint(udp, inet:socket(), inet:ip_address(), inet:port_number(),
                     ppspp_channel:channel()) ->  endpoint().

build_endpoint(udp, Socket, IP, Port, Channel) ->
    Channel_Name = convert:int_to_hex(ppspp_channel:get_channel_id(Channel)),
    Peer_as_String = peer_to_string(IP, Port),
    Endpoint_as_URI = lists:concat([ Peer_as_String, "#", Channel_Name]),
    ?DEBUG("dgram: received udp from ~s~n", [Endpoint_as_URI]),
    {endpoint, orddict:from_list([{ip, IP},
                                  Channel,
                                  {port, Port},
                                  {uri, Endpoint_as_URI},
                                  {transport, udp},
                                  {socket, Socket} ])}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc given an endpoint, returns the associated uri for comparison.
%% @spec
%% @end

-spec get_peer_uri(endpoint()) -> string().
get_peer_uri(Peer) -> get_peer_info(uri, Peer).

-spec get_peer_channel(endpoint()) -> ppspp_channel:channel().
get_peer_channel(Peer) -> get_peer_info(channel, Peer).

-spec get_peer_info(uri, endpoint()) -> any().
get_peer_info(Option, {endpoint, Peer_Dict}) ->
    orddict:fetch(Option, Peer_Dict).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc receives datagram from peer_worker, parses & delivers to matching channel
%% It's usually called from a spawned process, so return values are eventually
%% ignored.
%% @end

-spec handle_packet({udp, inet:socket(), inet:ip_address(), inet:port_number(),
              binary()}) -> ok.

handle_packet({udp, Socket, Peer_IP_Address, Peer_Port, Maybe_Datagram}) ->
    %% peek at channel to enable handling channel_zero case
    Channel = ppspp_channel:unpack_channel(Maybe_Datagram),
    Endpoint = build_endpoint(udp, Socket, Peer_IP_Address, Peer_Port, Channel),
    %% channel 0 gets special treatment, all other channels should already
    %% exist and be available for lookup in gproc to find associated swarm
    %% and options. The swarm options are required for the parser.
    {Datagram, Swarm_Options} =
    case ppspp_channel:is_channel_zero(Channel) of
        true -> unpack_on_channel_zero(Channel, Maybe_Datagram, Endpoint);
        false -> unpack_on_existing_channel(Channel, Maybe_Datagram, Endpoint)
    end,
    ?DEBUG("dgram: got valid datagram ~p~n", [Datagram]),
    handle_datagram(Datagram, Swarm_Options).

-spec unpack_on_channel_zero(ppspp_channel:channel(), binary(), endpoint()) ->
    {datagram(), ppspp_options:options()}.
%% we pass in our minimum options as only a handshake should come
%% in the same datagram, and we have as yet no agreed channel or options
%% for this peer / swarm / channel -- for example, this peer can manage many
%% swarms and we do not yet know to which swarm this packet / datagram belongs.
unpack_on_channel_zero(_Channel, Maybe_Datagram, Endpoint) ->
    Datagram = unpack(Maybe_Datagram, Endpoint,
                      ppspp_options:use_minimum_options()),
    {ok, Requested_Swarm_Options} = find_requested_swarm_options(Datagram),
    {Datagram, Requested_Swarm_Options}.

-spec unpack_on_existing_channel(ppspp_channel:channel(), binary(), endpoint()) ->
    {datagram(), ppspp_options:options()}.
unpack_on_existing_channel(Channel, Maybe_Datagram, Endpoint) ->
    {ok, Swarm_id} = ppspp_channel:get_swarm_id(Channel),
    {ok, Swarm_Options} = swarm_worker:get_swarm_options(Swarm_id),
    Datagram = unpack(Maybe_Datagram, Endpoint, Swarm_Options),
    {Datagram, Swarm_Options}.

-spec find_requested_swarm_options(datagram()) ->
    {ok, ppspp_options:options()} | {error, any()}.
find_requested_swarm_options(_Datagram) ->
    Swarm_id = "c89800bfc82ed01ed6e3bfd5408c51274491f7d4",
    {ok, ppspp_options:use_default_options(Swarm_id)}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Handle a fully unpacked datagram.
%% <p>  Each PPSPP datagram is complete in itself - relies only on the swarm
%% state for deciding what responses are needed. This handle function could
%% be transferred to a separate channel_worker process dedicated per peer.
%% </p>
%% @end

-spec handle_datagram(datagram(), ppspp_options:options()) -> ok.
handle_datagram({datagram, Datagram}, Swarm_Options) ->
    Endpoint = orddict:fetch(endpoint, Datagram),
    Messages = orddict:fetch(messages, Datagram),
    Mfun = fun Message(M) -> ppspp_message:handle(M) end,
    lists:foreach(Mfun, Messages),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc unpack a UDP packet into a PPSPP datagram using erlang term format
%% <p>  Deconstruct PPSPP UDP datagram into multiple erlang terms, including
%% <ul>
%% <li>Endpoint containing opaque information about Transport</li>
%% <li>list of Messages</li>
%% <li>Opaque orddict for Options, within a handshake message</li>
%% <ul>
%% A single datagram MAY contain multiple PPSPP messages; these will be handled
%% recursively as needed.
%% </p>
%% @end

-spec unpack(binary(), endpoint(), ppspp_options:options()) -> datagram().
unpack(Raw_Datagram, _Endpoint, Swarm_Options) ->
    {Channel, Maybe_Messages} = ppspp_channel:unpack_with_rest(Raw_Datagram),
    ?DEBUG("dgram: received on channel ~p~n",
           [convert:int_to_hex(ppspp_channel:get_channel_id(Channel))]),
    Parsed_Messages = ppspp_message:unpack(Maybe_Messages, Swarm_Options),
    %% TODO messages should probably be an opaque type in ppsppp_message.
    Parsed_Datagram = orddict:from_list([Endpoint, {messages, Parsed_Messages}]),
    {datagram, Parsed_Datagram}.

-spec pack(datagram()) -> binary().
pack(_Datagram) -> <<>>.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% test

% -ifdef(TEST).
% -spec _test() -> {ok, pid()}.
% _test() ->
%     start(),
%     ?assertMatch({ok, _}, ).
% -endif.
