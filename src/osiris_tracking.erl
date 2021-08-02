-module(osiris_tracking).

-include("osiris.hrl").

-export([
         init/1,
         add/5,
         flush/1,
         snapshot/3,
         query/3,
         append_trailer/3,
         needs_flush/1,
         is_empty/1,
         overview/1
         ]).

-define(MAX_WRITERS, 255).
%% holds static or rarely changing fields
-record(cfg, {}).

-type tracking_id() :: binary().
-type tracking_type() :: sequence | offset | timestamp.
-type tracking() :: non_neg_integer() | osiris:offset() | osiris:timestamp().

-record(?MODULE, {cfg = #cfg{} :: #cfg{},
                  pending = init_pending() :: #{sequences | offsets | timestamps =>
                                                #{tracking_id() => tracking()}},
                  sequences = #{} :: #{osiris:writer_id() => {osiris:offset(), non_neg_integer()}},
                  offsets = #{} :: #{tracking_id() => osiris:offset()},
                  timestamps = #{} :: #{tracking_id() => osiris:timestamp()}
                 }).

-opaque state() :: #?MODULE{}.

-export_type([
              state/0,
              tracking_type/0,
              tracking_id/0
              ]).

init_pending() ->
    #{sequences => #{},
      offsets => #{},
      timestamps => #{}}.

-spec init(undefined | binary()) -> state().
init(undefined) ->
    #?MODULE{};
init(Bin) when is_binary(Bin) ->
    parse_snapshot(Bin, #?MODULE{}).

-spec add(tracking_id(), tracking_type(), tracking(), osiris:offset() | undefined,
          state()) -> state().
add(TrkId, TrkType, TrkData, ChunkId,
    #?MODULE{pending = Pend0} = State) when is_integer(TrkData) andalso
                                            byte_size(TrkId) =< 256 ->
    Type = plural(TrkType),
    Trackings0 = maps:get(Type, Pend0),
    Trackings1 = Trackings0#{TrkId => TrkData},
    Pend = Pend0#{Type := Trackings1},
    update_tracking(TrkId, TrkType, TrkData,
                    ChunkId, State#?MODULE{pending = Pend}).

%% Convert for example 'offset' to 'offsets'.
plural(Word) when is_atom(Word) ->
    list_to_atom(atom_to_list(Word) ++ "s").

-spec flush(state()) -> {iodata(), state()}.
flush(#?MODULE{pending = Pending} = State) ->
    TData = maps:fold(fun(TrkType, TrackingMap, Acc) ->
                              T = case TrkType of
                                      sequences ->
                                          ?TRK_TYPE_SEQUENCE;
                                      offsets ->
                                          ?TRK_TYPE_OFFSET;
                                      timestamps ->
                                          ?TRK_TYPE_TIMESTAMP
                                  end,
                              TData0 = maps:fold(fun(TrkId, TrkData, Acc0) ->
                                                         [<<T:8/unsigned,
                                                            (byte_size(TrkId)):8/unsigned,
                                                            TrkId/binary,
                                                            TrkData:64/integer>> | Acc0]
                                                 end, [], TrackingMap),
                              [TData0| Acc]
                      end, [], Pending),
    {TData, State#?MODULE{pending = init_pending()}}.

-spec snapshot(osiris:offset(), osiris:timestamp(), state()) ->
    {iodata(), state()}.
snapshot(FirstOffset, FirstTimestamp, #?MODULE{sequences = Seqs0,
                                               offsets = Offsets0,
                                               timestamps = Timestamps0} = State) ->
    %% discard any tracking info with offsets lower than the first offset
    %% in the stream
    Offsets = maps:filter(fun(_, Off) -> Off >= FirstOffset end, Offsets0),
    %% discard any tracking info with timestamps lower than the first
    %% timestamp in the stream
    Timestamps = maps:filter(fun(_, Ts) -> Ts >= FirstTimestamp end, Timestamps0),
    Seqs = trim_writers(?MAX_WRITERS, Seqs0),

    Data0 = maps:fold(fun(TrkId, {ChId, Seq} , Acc) ->
                                [<<?TRK_TYPE_SEQUENCE:8/unsigned,
                                   (byte_size(TrkId)):8/unsigned,
                                   TrkId/binary,
                                   ChId:64/unsigned,
                                   Seq:64/unsigned>>
                                 | Acc]
                        end, [], Seqs),
    Data1 = maps:fold(fun(TrkId, Offs, Acc) ->
                             [<<?TRK_TYPE_OFFSET:8/unsigned,
                                (byte_size(TrkId)):8/unsigned,
                                TrkId/binary,
                                Offs:64/unsigned>>
                              | Acc]
                     end, Data0, Offsets),
    Data2 = maps:fold(fun(TrkId, Ts, Acc) ->
                             [<<?TRK_TYPE_TIMESTAMP:8/unsigned,
                                (byte_size(TrkId)):8/unsigned,
                                TrkId/binary,
                                Ts:64/signed>>
                              | Acc]
                     end, Data1, Timestamps),
    {Data2, State#?MODULE{pending = init_pending(),
                          sequences = Seqs,
                          offsets = Offsets,
                          timestamps = Timestamps}}.

-spec query(tracking_id(), TrkType :: tracking_type(), state()) ->
    {ok, term()} | {error, not_found}.
query(TrkId, sequence, #?MODULE{sequences = Seqs})
  when is_binary(TrkId) ->
    case Seqs of
        #{TrkId := Tracking} ->
            {ok, Tracking};
        _ ->
            {error, not_found}
    end;
query(TrkId, offset, #?MODULE{offsets = Offs})
  when is_binary(TrkId) ->
    case Offs of
        #{TrkId := Tracking} ->
            {ok, Tracking};
        _ ->
            {error, not_found}
    end;
query(TrkId, timestamp, #?MODULE{timestamps = Timestamps})
  when is_binary(TrkId) ->
    case Timestamps of
        #{TrkId := Tracking} ->
            {ok, Tracking};
        _ ->
            {error, not_found}
    end.

-spec append_trailer(osiris:offset(), binary(), state()) ->
    state().
append_trailer(ChId, Bin, State) ->
    parse_trailer(Bin, ChId, State).

-spec needs_flush(state()) -> boolean().
needs_flush(#?MODULE{pending = #{sequences := Sequences,
                                 offsets := Offsets,
                                 timestamps := Timestamps}}) ->
    map_size(Sequences) > 0 orelse
    map_size(Offsets) > 0 orelse
    map_size(Timestamps) > 0.

-spec is_empty(state()) -> boolean().
is_empty(#?MODULE{sequences = Seqs, offsets = Offs, timestamps = Timestamps}) ->
    map_size(Seqs) + map_size(Offs) + map_size(Timestamps) == 0.

-spec overview(state()) -> map(). %% TODO refine
overview(#?MODULE{sequences = Seqs, offsets = Offs, timestamps = Timestamps}) ->
    #{offsets => Offs,
      sequences => Seqs,
      timestamps => Timestamps}.

%% INTERNAL
update_tracking(TrkId, sequence, Tracking, ChId,
                #?MODULE{sequences = Seqs0} = State) when is_integer(ChId) ->
    State#?MODULE{sequences = Seqs0#{TrkId => {ChId, Tracking}}};
update_tracking(TrkId, offset, Tracking, _ChId,
                #?MODULE{offsets = Offs} = State) ->
    State#?MODULE{offsets = Offs#{TrkId => Tracking}};
update_tracking(TrkId, timestamp, Tracking, _ChId,
                #?MODULE{timestamps = Timestamps} = State) ->
    State#?MODULE{timestamps = Timestamps#{TrkId => Tracking}}.

parse_snapshot(<<>>, State) ->
    State;
parse_snapshot(<<?TRK_TYPE_SEQUENCE:8/unsigned,
                 TrkIdSize:8/unsigned,
                 TrkId:TrkIdSize/binary,
                 ChId:64/unsigned,
                 Seq:64/unsigned, Rem/binary>>,
               #?MODULE{sequences = Seqs} = State) ->
    parse_snapshot(Rem, State#?MODULE{sequences = Seqs#{TrkId => {ChId, Seq}}});
parse_snapshot(<<?TRK_TYPE_OFFSET:8/unsigned,
                 TrkIdSize:8/unsigned,
                 TrkId:TrkIdSize/binary,
                 Offs:64/unsigned, Rem/binary>>,
               #?MODULE{offsets = Offsets} = State) ->
    parse_snapshot(Rem, State#?MODULE{offsets = Offsets#{TrkId => Offs}});
parse_snapshot(<<?TRK_TYPE_TIMESTAMP:8/unsigned,
                 TrkIdSize:8/unsigned,
                 TrkId:TrkIdSize/binary,
                 Ts:64/signed, Rem/binary>>,
               #?MODULE{timestamps = Timestamps} = State) ->
    parse_snapshot(Rem, State#?MODULE{timestamps = Timestamps#{TrkId => Ts}}).

parse_trailer(<<>>, _ChId, State) ->
    State;
parse_trailer(<<?TRK_TYPE_SEQUENCE:8/unsigned,
                TrkIdSize:8/unsigned,
                TrkId:TrkIdSize/binary,
                Seq:64/unsigned, Rem/binary>>,
              ChId, #?MODULE{sequences = Seqs} = State) ->
    parse_trailer(Rem, ChId, State#?MODULE{sequences = Seqs#{TrkId => {ChId, Seq}}});
parse_trailer(<<?TRK_TYPE_OFFSET:8/unsigned,
                TrkIdSize:8/unsigned,
                TrkId:TrkIdSize/binary,
                Offs:64/unsigned, Rem/binary>>,
              ChId, #?MODULE{offsets = Offsets} = State) ->
    parse_trailer(Rem, ChId, State#?MODULE{offsets = Offsets#{TrkId => Offs}});
parse_trailer(<<?TRK_TYPE_TIMESTAMP:8/unsigned,
                TrkIdSize:8/unsigned,
                TrkId:TrkIdSize/binary,
                Ts:64/signed, Rem/binary>>,
              ChId, #?MODULE{timestamps = Timestamps} = State) ->
    parse_trailer(Rem, ChId, State#?MODULE{timestamps = Timestamps#{TrkId => Ts}}).

trim_writers(Max, Writers) when map_size(Writers) =< Max ->
    Writers;
trim_writers(Max, Writers) ->
    Sorted = lists:sort(fun ({_, {C0, _}}, {_, {C1, _}}) ->
                                C0 < C1
                        end, maps:to_list(Writers)),
    maps:from_list(lists:nthtail(map_size(Writers) - Max, Sorted)).
