%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2021 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(osiris_tracking_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-export([]).

% -include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(TRK_TYPE_SEQUENCE, 0).
-define(TRK_TYPE_OFFSET, 1).
-define(TRK_TYPE_TIMESTAMP, 2).
%%%===================================================================
%%% Common Test callbacks
%%%===================================================================

all() ->
    [{group, tests}].

all_tests() -> [basics,
               recover].

groups() ->
    [{tests, [], all_tests()}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%%===================================================================
%%% Test cases
%%%===================================================================

basics(_Config) ->
    T0 = osiris_tracking:init(undefined),
    ChId1 = ?LINE,
    T1 = osiris_tracking:add(<<"w1">>, sequence, 55, ChId1, T0),
    ?assert(osiris_tracking:needs_flush(T1)),
    ?assertEqual({ok, {ChId1, 55}}, osiris_tracking:query(<<"w1">>, sequence, T1)),
    ?assertEqual({error, not_found}, osiris_tracking:query(<<"w2">>, sequence, T1)),
    {Trailer1, T2} = osiris_tracking:flush(T1),
    ?assert(false == osiris_tracking:needs_flush(T2)),
    ?assertMatch(<<?TRK_TYPE_SEQUENCE:8,
                   2:8/unsigned,
                   "w1", 55:64/unsigned>>,
                 iolist_to_binary(Trailer1)),

    ChId2 = ?LINE,
    T3 = osiris_tracking:add(<<"t1">>, offset, 99, ChId2, T2),
    ?assertEqual({ok, 99}, osiris_tracking:query(<<"t1">>, offset, T3)),
    {Trailer2, T4} = osiris_tracking:flush(T3),
    ?assertMatch(<<?TRK_TYPE_OFFSET:8,
                   2:8/unsigned,
                   "t1", 99:64/unsigned>>,
                 iolist_to_binary(Trailer2)),

    ChId3 = ?LINE,
    Ts = 1626773300252,
    T5 = osiris_tracking:add(<<"t2">>, timestamp, Ts, ChId3, T4),
    ?assertEqual({ok, Ts}, osiris_tracking:query(<<"t2">>, timestamp, T5)),
    {Trailer3, T6} = osiris_tracking:flush(T5),
    ?assertMatch(<<?TRK_TYPE_TIMESTAMP:8,
                   2:8/unsigned,
                   "t2", Ts:64/signed>>,
                 iolist_to_binary(Trailer3)),

    %% ensure negative timestamps work (although they shouldn't be used in practice)
    ChId4 = ?LINE,
    NegativeTs = -9,
    T7 = osiris_tracking:add(<<"t3">>, timestamp, NegativeTs, ChId4, T6),
    ?assertEqual({ok, NegativeTs}, osiris_tracking:query(<<"t3">>, timestamp, T7)),
    {Trailer4, T8} = osiris_tracking:flush(T7),
    ?assertMatch(<<?TRK_TYPE_TIMESTAMP:8,
                   2:8/unsigned,
                   "t3", NegativeTs:64/signed>>,
                 iolist_to_binary(Trailer4)),

    {Snap1, _T9} = osiris_tracking:snapshot(99, NegativeTs, T8),
    ?assertMatch(<<?TRK_TYPE_TIMESTAMP:8/unsigned,
                   2:8/unsigned,
                   "t3",
                   NegativeTs:64/signed,
                   ?TRK_TYPE_TIMESTAMP:8/unsigned,
                   2:8/unsigned,
                   "t2",
                   Ts:64/signed,
                   ?TRK_TYPE_OFFSET:8/unsigned,
                   2:8/unsigned,
                   "t1",
                   99:64/unsigned,
                   ?TRK_TYPE_SEQUENCE:8/unsigned,
                   2:8/unsigned,
                   "w1",
                   ChId1:64/unsigned,
                   55:64/unsigned>>, iolist_to_binary(Snap1)),
    %% tracking offsets lower than first offset in stream should be discarded
    %% tracking timestamps lower than first timestamp in stream should be discarded
    {Snap2, _T10} = osiris_tracking:snapshot(100, Ts+1, T8),
    ?assertMatch(<<?TRK_TYPE_SEQUENCE:8/unsigned,
                   2:8/unsigned,
                   "w1",
                   ChId1:64/unsigned,
                   55:64/unsigned>>, iolist_to_binary(Snap2)),
    ok.


recover(_Config) ->
    ChId1 = ?LINE,
    Ts1 = 1626999999,
    SnapBin = <<?TRK_TYPE_OFFSET:8/unsigned,
                2:8/unsigned,
                "t1",
                99:64/unsigned,
                ?TRK_TYPE_TIMESTAMP:8/unsigned,
                2:8/unsigned,
                "t2",
                Ts1:64/signed,
                ?TRK_TYPE_SEQUENCE:8/unsigned,
                2:8/unsigned,
                "w1",
                ChId1 :64/unsigned,
                55:64/unsigned>>,

    T0 = osiris_tracking:init(SnapBin),
    ?assertEqual({ok, {ChId1, 55}}, osiris_tracking:query(<<"w1">>, sequence, T0)),
    ?assertEqual({ok, 99}, osiris_tracking:query(<<"t1">>, offset, T0)),
    ?assertEqual({ok, Ts1}, osiris_tracking:query(<<"t2">>, timestamp, T0)),

    Ts2 = Ts1 + 5,
    Trailer = <<?TRK_TYPE_OFFSET:8/unsigned,
                2:8/unsigned,
                "t3",
                103:64/unsigned,
                ?TRK_TYPE_TIMESTAMP:8/unsigned,
                2:8/unsigned,
                "t4",
                Ts2:64/signed,
                ?TRK_TYPE_SEQUENCE:8/unsigned,
                2:8/unsigned,
                "w2",
                77:64/unsigned>>,

    ChId2 = ?LINE,
    T1 = osiris_tracking:append_trailer(ChId2, Trailer, T0),
    ?assertEqual({ok, {ChId1, 55}}, osiris_tracking:query(<<"w1">>, sequence, T1)),
    ?assertEqual({ok, {ChId2, 77}}, osiris_tracking:query(<<"w2">>, sequence, T1)),
    ?assertEqual({ok, 99}, osiris_tracking:query(<<"t1">>, offset, T1)),
    ?assertEqual({ok, Ts1}, osiris_tracking:query(<<"t2">>, timestamp, T1)),
    ?assertEqual({ok, 103}, osiris_tracking:query(<<"t3">>, offset, T1)),
    ?assertEqual({ok, Ts2}, osiris_tracking:query(<<"t4">>, timestamp, T1)),
    ok.
