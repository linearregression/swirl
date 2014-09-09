%%%----FILE ppspp_records.hrl----

-include("../include/ppspp.hrl").

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

%%%----END FILE----
