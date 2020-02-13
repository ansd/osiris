-module(osiris).

-export([
         start_cluster/2,
         start_cluster/3,
         stop_cluster/2,
         write/3,
         restart_cluster/2,
         restart_server/2,
         restart_server/3,
         restart_replica/3,
         restart_replica/4,
         delete_cluster/4
         ]).

-define(BASE64_URI_CHARS,
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "abcdefghijklmnopqrstuvwxyz"
        "0123456789_-=").

%% holds static or rarely changing fields
-record(cfg, {}).

-record(?MODULE, {cfg :: #cfg{}}).

-opaque state() :: #?MODULE{}.

-export_type([
              state/0
              ]).

-spec start_cluster(string(), [node()]) ->
    {ok, pid(), [pid()]}.
start_cluster(Name0, Replicas) ->
    start_cluster(Name0, Replicas, #{}).

start_cluster(Name0, Replicas, Config)
  when is_list(Name0) orelse
       is_atom(Name0) orelse
       is_binary(Name0) ->
    %% Why does the name have to be a list? We need an atom as process name
    %% for the gen_batch_server
    true = validate_base64uri(to_string(Name0)),
    Name = list_to_atom(Name0),
    {ok, Pid} = osiris_writer:start(Name, Config#{replica_nodes => Replicas}),
    ReplicaPids = [begin
                       {ok, P} = osiris_replica:start(N, Name, Config#{leader_pid => Pid}),
                       P
                   end || N <- Replicas],
    {ok, Pid, ReplicaPids}.

stop_cluster(Name0, Replicas)
  when is_list(Name0) orelse
       is_atom(Name0) orelse
       is_binary(Name0) ->
    true = validate_base64uri(to_string(Name0)),
    Name = list_to_atom(Name0),
    ok = osiris_writer:stop(Name),
    [ok = osiris_replica:stop(N, Name) || N <- Replicas],
    ok.

-spec delete_cluster(any(), node(), [node()], #{}) -> ok.
delete_cluster(Name, Leader, Replicas, Config) ->
    [ok = osiris_replica:delete(Name, R, Config) || R <- Replicas],
    ok = osiris_writer:delete(Name, Leader, Config).

restart_cluster(Name0, Replicas) ->
    restart_cluster(Name0, Replicas, #{}).

restart_cluster(Name0, Replicas, Config)
  when is_list(Name0) orelse
       is_atom(Name0) orelse
       is_binary(Name0) ->
    %% Why does the name have to be a list? We need an atom as process name
    %% for the gen_batch_server
    true = validate_base64uri(to_string(Name0)),
    Name = list_to_atom(Name0),
    {ok, Pid} = osiris_writer:start(Name, Config#{replica_nodes => Replicas}),
    ReplicaPids = [element(2, osiris_replica:start(N, Name,
                                                   Config#{leader_pid => Pid}))
                   || N <- Replicas],
    {ok, Pid, ReplicaPids}.

restart_server(Name, Replicas) ->
    restart_server(Name, Replicas, #{}).

restart_server(Name, Replicas, Config)
  when is_atom(Name) ->
    %% Why does the name have to be a list? We need an atom as process name
    %% for the gen_batch_server
    osiris_writer:start(Name, Config#{replica_nodes => Replicas}).

restart_replica(Name, Leader, Replica) ->
    restart_replica(Name, Leader, Replica, #{}).

restart_replica(Name, Leader, Replica, Config)
  when is_atom(Name) ->
    osiris_replica:start(Replica, Name, Config#{leader_pid => Leader}).

write(Pid, Corr, Data) ->
    osiris_writer:write(Pid, self(), Corr, Data).


-spec validate_base64uri(string()) -> boolean().
validate_base64uri(Str) when is_list(Str) ->
    catch
    begin
        [begin
             case lists:member(C, ?BASE64_URI_CHARS) of
                 true -> ok;
                 false -> throw(false)
             end
         end || C <- string:to_graphemes(Str)],
        string:is_empty(Str) == false
    end.

to_string(B) when is_binary(B) ->
    binary_to_list(B);
to_string(A) when is_atom(A) ->
    atom_to_list(A);
to_string(S) when is_list(S) ->
    S.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
