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

-module(ppspp_handshake).
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-spec test() -> term().
-endif.

%% api
-export([unpack/1,
         pack/1,
         handle/1]).

-opaque handshake() :: {handshake,
                        ppspp_channel:channel(),
                        ppspp_options:options()}.
-export_type([handshake/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc unpack a handshake message
%% <p>  Deconstruct PPSPP UDP datagram into multiple erlang terms, including
%% parsing any additional data within the same segment. Any parsing failure
%% is fatal & will propagate back to the attempted datagram unpacking.
%% </p>
%% @end

-spec unpack(binary()) -> {handshake(), binary()}.

unpack(Message) ->
    {Channel, Maybe_Options} = ppspp_channel:unpack_with_rest(Message),
    {Maybe_Messages, Options} = ppspp_options:unpack(Maybe_Options),
    {{handshake, Channel, Options}, Maybe_Messages}.

-spec pack(ppspp_message:message()) -> binary().
pack(_Message) -> <<>>.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% The payload of the HANDSHAKE message is a channel ID (see
%%  Section 3.11) and a sequence of protocol options.  Example options
%%  are the content integrity protection scheme used and an option to
%%  specify the swarm identifier.  The complete set of protocol options
%%  are specified in Section 7.
%%
%% handshake needs the endpoint info, and will set up a new channel if the
%% requested swarm is available, and the options are compatible. The linking
%% of the swarm and external peer's address together should be registered
%% with the swarm handler.
%%
%%  {handshake,
%%    {channel,3349748573},
%%    {options,
%%     [{chunk_addressing_method,
%%       chunking_32bit_chunks},
%%      {chunk_size,1024},
%%      {content_integrity_check_method,
%%       merkle_hash_tree},
%%      {merkle_hash_tree_function,sha},
%%      {minimum_version,1},
%%      {swarm_id,
%%       <<200,152,0,191,200,46,208,30,214,
%%         227,191,213,64,140,81,39,68,145,
%%         247,212>>},
%%      {version,1}]}}.
-spec handle(ppspp_message:message()) -> any().

handle({handshake, _Body}) ->
    {ok, ppspp_message_handler_not_yet_implemented};

handle(Message) ->
    ?DEBUG("message: handler not yet implemented ~p~n", [Message]),
    {ok, ppspp_message_handler_not_yet_implemented}.
