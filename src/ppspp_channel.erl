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

-module(ppspp_channel).
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-spec test() -> term().
-endif.

%% api
-export([unpack_channel/1,
         unpack_with_rest/1,
         pack/1,
         where_is/1,
         acquire_channel/1,
         release_channel/1,
         channel_to_string/1,
         handle/1]).

-opaque channel() :: {channel, channel_option()}.
-opaque channel_option() :: 0..16#ffffffff.
-export_type([channel/0, channel_option/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc unpack a channel message
%% <p>  Deconstruct PPSPP UDP datagram into multiple erlang terms, including
%% parsing any additional data within the same segment. Any parsing failure
%% is fatal & will propagate back to the attempted datagram unpacking.
%% </p>
%% @end

-spec unpack_with_rest(binary()) -> {channel(), binary()}.

unpack_with_rest(<<Channel:?PPSPP_CHANNEL_SIZE, Rest/binary>>) ->
    {{channel, Channel}, Rest}.

-spec unpack_channel(binary()) -> channel().
unpack_channel(Binary) ->
    {Channel, _Rest} = unpack_with_rest(Binary),
    Channel.

-spec channel_to_string(channel()) -> string().
channel_to_string(_Channel = {channel, Channel}) ->
    string:to_lower(integer_to_list(Channel, 16)).

-spec pack(ppspp_message:message()) -> binary().
pack(_Message) -> <<>>.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% acquire_channel
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc allow requesting process to register an unused channel
%% <p> Ensure that the channel can  be searched for using the swarm id.
%% A increasing delay is imposed on requesting channels as usage increases
%% proportional to the previous failed tries, as a way of controlling overall
%% load for new requesters. The timeout is approximately 60 seconds.
%% </p>
%% @end
-spec acquire_channel(ppspp_options:swarm_id()) -> channel().
acquire_channel(Swarm_id) ->
    Channel = find_free_channel(Swarm_id, 0),
    {channel, Channel}.

-spec find_free_channel(ppspp_options:swarm_id(), pos_integer()) ->
    channel() | {error, any()}.
find_free_channel(_, 30) -> {error, ppspp_channel_no_channels_free};
find_free_channel(Swarm_id, Failed_Tries) when Failed_Tries < 30 ->
    timer:sleep(Failed_Tries * 1000),
    <<Maybe_Free_Channel:?DWORD>> = crypto:strong_rand_bytes(4),
    Channel = {channel, Maybe_Free_Channel},
    Key = {n, l, Channel},
    Self = self(),
    %% channel is unique only when returned pid matches self, otherwise
    %% just try again for a new random channel and increased timeout
    case gproc:reg_or_locate(Key, Swarm_id) of
        {Self, Swarm_id} -> Maybe_Free_Channel;
        {_, _ } -> find_free_channel(Swarm_id, Failed_Tries + 1)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% release_channel
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc allow requesting process to release an assigned channel
%% <p> This function will crash if the channel was not registered to this
%% process, as gproc returns badarg in this case.
%% </p>
%% @end
-spec release_channel(channel()) -> ok.
release_channel(Channel) ->
    case gproc:unreg({n,l, Channel}) of
        true -> ok;
        _ -> {error, ppspp_channel_free_unassigned_channel}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% where_is
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc looks up pid of the owning swarm for a given channel
%% <p> Channels are only registered to swarm_workers; and peer_worker however
%% may receive inbound packets for a particular swarm and will use the received
%% channel to look it up before retrieving swarm options. It is used to locate
%% the owning swarm in a channel when unpacking messages.
%% </p>
%% @end

-spec where_is(channel()) -> {ok, pid()} | {error, any()}.
where_is(Ref = {channel, _}) ->
    case Pid = gproc:lookup_local_name(Ref) of
        undefined -> {error, ppspp_channel_not_found};
        _ -> {ok, Pid}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%-spec ... handle takes a tuple of {type, message_body} where body is a
%%    parsed orddict message and returns either
%%    {error, something} or tagged tuple for the unpacked message
%%    {ok, reply} where reply is probably an orddict to be sent to the
%%    alternate peer.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The payload of the channel message is a channel ID (see
%  Section 3.11) and a sequence of protocol options.  Example options
%  are the content integrity protection scheme used and an option to
%  specify the swarm identifier.  The complete set of protocol options
%  are specified in Section 7.
-spec handle(ppspp_message:message()) -> any().
handle({channel, _Body}) ->
    {ok, ppspp_message_handler_not_yet_implemented};

handle(Message) ->
    ?DEBUG("message: handler not yet implemented ~p~n", [Message]),
    {ok, ppspp_message_handler_not_yet_implemented}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% test

% -ifdef(TEST).
% -spec _test() -> {ok, pid()}.
% _test() ->
%     start(),
%     ?assertMatch({ok, _}, ).
% -endif.
