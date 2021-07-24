%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2020 VMware, Inc. or its affiliates.  All rights reserved.
%%

%% logging shim
-define(DEBUG(Fmt, Args), ?DISPATCH_LOG(debug, Fmt, Args)).
-define(DEBUG_IF(Fmt, Args, Bool),
        if Bool ->
               ?DISPATCH_LOG(debug, Fmt, Args);
           true -> ok
        end).
-define(INFO(Fmt, Args), ?DISPATCH_LOG(info, Fmt, Args)).
-define(NOTICE(Fmt, Args), ?DISPATCH_LOG(notice, Fmt, Args)).
-define(WARN(Fmt, Args), ?DISPATCH_LOG(warning, Fmt, Args)).
-define(WARNING(Fmt, Args), ?DISPATCH_LOG(warning, Fmt, Args)).
-define(ERR(Fmt, Args), ?DISPATCH_LOG(error, Fmt, Args)).
-define(ERROR(Fmt, Args), ?DISPATCH_LOG(error, Fmt, Args)).

-define(DISPATCH_LOG(Level, Fmt, Args),
        %% same as OTP logger does when using the macro
        catch (persistent_term:get('$osiris_logger')):log(Level, Fmt, Args,
                                                          #{mfa => {?MODULE,
                                                                    ?FUNCTION_NAME,
                                                                    ?FUNCTION_ARITY},
                                                            file => ?FILE,
                                                            line => ?LINE,
                                                            domain => [osiris]}),
       ok).

-define(C_NUM_LOG_FIELDS, 5).

-define(MAGIC, 5).
%% chunk format version
-define(VERSION, 0).
-define(HEADER_SIZE_B, 48).
-define(FILE_OPTS_WRITE, [raw, binary, write, read]).


%% chunk types
-define(CHNK_USER, 0).
-define(CHNK_TRK_DELTA, 1).
-define(CHNK_TRK_SNAPSHOT, 2).
-define(CHUNK_TYPE_INT_TO_ATOM(T),
        case T of
            ?CHNK_USER ->
                chunk_user;
            ?CHNK_TRK_DELTA ->
                chunk_tracking_delta;
            ?CHNK_TRK_SNAPSHOT ->
                chunk_tracking_snapshot
        end).

-define(TRK_TYPE_SEQUENCE, 0).
-define(TRK_TYPE_OFFSET, 1).

%% Compression types for sub batch entries.
%% Osiris defines these types but only clients (un)compress.
-define(COMPRESS_TYPE_NONE, 0).
-define(COMPRESS_TYPE_GZIP, 1).
-define(COMPRESS_TYPE_SNAPPY, 2).
-define(COMPRESS_TYPE_LZ4, 3).
-define(COMPRESS_TYPE_ZSTD, 4).
-define(COMPRESS_TYPE_RSVD1, 5).
-define(COMPRESS_TYPE_RSVD2, 6).
-define(COMPRESS_TYPE_USER, 7).
-define(COMPRESS_TYPE_INT_TO_ATOM(T),
        case T of
            ?COMPRESS_TYPE_NONE ->
                compression_none;
            ?COMPRESS_TYPE_GZIP ->
                compression_gzip;
            ?COMPRESS_TYPE_SNAPPY ->
                compression_snappy;
            ?COMPRESS_TYPE_LZ4 ->
                compression_lz4;
            ?COMPRESS_TYPE_ZSTD ->
                compression_zstd;
            ?COMPRESS_TYPE_RSVD1 ->
                compression_reserved_1;
            ?COMPRESS_TYPE_RSVD2 ->
                compression_reserved_2;
            ?COMPRESS_TYPE_USER ->
                compression_user_defined
        end).

-define(SUP, osiris_server_sup).
