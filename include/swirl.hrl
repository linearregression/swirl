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

-include("ppspp.hrl").
-ifndef(SWIRL_PORT).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% application macros
-define(SWIRL_PORT, 7777).
-define(SWIRL_APP, swirl).

%% maximum PPSP protocol version that swirl supports
-define(SWIRL_MAX_PPSPP_VERSION, 1).

-define(DEBUG(Format, Args), error_logger:info_msg(Format,    Args)).
-define(ERROR(Format, Args), error_logger:error_msg(Format,   Args)).
-define(WARN(Format, Args),  error_logger:warning_msg(Format, Args)).
-define(INFO(Format, Args),  error_logger:info_msg(Format,    Args)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% records used throughout app

-type version()     :: 1..255.
%% server type defines the role of the server.
-type peer_type()     :: static | live | injector.
-type leecher_state() :: tune_in | streaming | normal.

-record(options, {
          %% SWARM options
          ppspp_swarm_id                     :: bitstring(),
          ppspp_version                      :: version(), 
          ppspp_minimum_version              :: version() ,
          ppspp_chunking_method              :: byte(),
          ppspp_integrity_check_method       :: byte(),
          ppspp_merkle_hash_function         :: byte(),
          ppspp_live_signature_algorithm,
          ppspp_live_discard_window
          %% supported_messges,
         }).

-record(peer, {
          %% SERVER state variables
          %% type : static live or injector
          type                        :: peer_type(),

          %% state : for leecher i.e. tune_in, streaming, normal
          state                       :: leecher_state(),

          %% server_data (orddict) will contain different variables that need
          %% to be stored for operations involving datagrams from different
          %% peers.
          %% incase of live stream, leecher may store HAVE payload:
          %%    have : to track the highest munro among different HAVEs.
          %%    have_peers: peers having the highest munro for tune_in.
          server_data = orddict:new() :: orddict:orddict(),

          %% holds state of all peers with whom the server is interacting
          peer_table                  :: atom(),

          %% name of the peer whose request is being processed.
          peer                        :: atom() | string(),

          %% peer_state holds state of current peer with whom the server is
          %% talking. It will be loaded from the table and may contain
          %% following depending on the server type (seeder/leecher) and role
          %% (live/static).
          %% for live leecher we may have following :
          %%    integrity : will contain a list {Bin, Hash} received from the
          %%    particular peer. NOTE : these will used to validate DATA once
          %%    it arrives, after which they will be removed from the state.
          %% for live seeder we may have the following :
          %%    ack_range : Bins corresponding to the range of DATA that the
          %%    peer has received.
          peer_state                  :: orddict:orddict(),

          %% name of the merkle tree
          mtree                       :: atom(),

          %% SWARM options
          options =
          #options{
             ppspp_version         = ?PPSPP_CURRENT_VERSION,
             ppspp_minimum_version = ?PPSPP_CURRENT_VERSION,
             ppspp_chunking_method = ?PPSPP_DEFAULT_CHUNK_ADDRESSING_METHOD,
             ppspp_merkle_hash_function = ?PPSPP_DEFAULT_MERKLE_HASH_FUNCTION
            }
         }).

-endif.
