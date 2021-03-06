defmodule DictatorGame.Participant do
  alias DictatorGame.Actions

  def filter_data(data, id) do
    pair_id = get_in(data, [:participants, id, :pair_id])
    rule = %{
      dynamic_text: true,
      page: true,
      game_progress: true,
      game_round: true,
      game_progress: true,
      participants: %{id => true},
      pairs: %{pair_id => %{
        pair_results: true,
        members: true,
        now_round: true,
        allo_temp: true,
        state: true,
      }},
      dictator_results: data.page == "result",
      _spread: [[:participants, id], [:pairs, pair_id]]
    }
    data
    |> Transmap.transform(rule)
    |> Map.put(:participants_length, Map.size(data.participants))
    |> Map.put(:id, id)
  end

  # Actions
  def fetch_contents(data, id) do
    Actions.update_participant_contents(data, id)
  end

  def change_allo_temp(data, id, allo_temp) do
    pair_id = get_in(data, [:participants, id, :pair_id])
    "allocating" = get_in(data, [:pairs, pair_id, :state])
    put_in(data, [:pairs, pair_id, :allo_temp], allo_temp)
  end

  def finish_allocating(data, id, allo_temp) do
    pair_id = get_in(data, [:participants, id, :pair_id])
    put_in(data, [:pairs, pair_id, :state], "judging")
  end

  def get_next_role(role) do
    case role == "responder" do
      true -> "dictator"
      false -> "responder"
    end
  end

  def response(data, id, result) do
    value = get_in(result, ["value"])
    change_count = get_in(result, ["change_count"])
    now_round = get_in(result, ["now_round"])
    pair_id = get_in(data, [:participants, id, :pair_id])
    game_round = get_in(data, [:game_round])
    members = get_in(data, [:pairs, pair_id, :members])
    target_id = case members do
      [^id, target_id] -> target_id
      [target_id, ^id] -> target_id
    end
    id_role = get_in(data, [:participants, id, :role])
    target_id_role = get_in(data, [:participants, target_id, :role])
    id_point = get_in(data, [:participants, id, :point])
    target_id_point = get_in(data, [:participants, target_id, :point])
    put_in(data, [:participants, id, :role], get_next_role(id_role))
    |> put_in([:participants, target_id, :role], get_next_role(target_id_role))
    |> put_in([:participants, id, :point],
      case id_role == "responder" do
         true -> id_point + (1000 - value)
         false -> id_point + value
      end
    )
    |> put_in([:participants, target_id, :point],
      case target_id_role == "responder" do
         true -> target_id_point + (1000 - value)
         false -> target_id_point + value
      end
    )
    |> put_in([:pairs, pair_id, :redo_count], 0)
    |> put_in([:pairs, pair_id, :state],
     case now_round < game_round do
       true -> "allocating"
       false -> "finished"
     end
    )
    |> put_in([:pairs, pair_id, :now_round],
    case now_round < game_round do
      true -> now_round + 1
      false -> now_round
    end
    )
    |> update_in([:pairs, pair_id, :pair_results], fn list ->
      [%{dictator: target_id, value: value} | list]
    end)
    |> put_in([:dictator_results], Map.merge( get_in(data, [:dictator_results]), %{
      Integer.to_string(now_round) => Map.merge( get_in(data, [:dictator_results,
         Integer.to_string(now_round)]) || %{}, %{
        pair_id => %{
            value: value,
            change_count: change_count,
          }
       })
    }))
    |> compute_progress
  end

  defp compute_progress(data) do
    pairs_length = Map.size(data.pairs)
    finished = Enum.count(data.pairs, fn {_id, %{state: state}} -> state == "finished" end)
    %{data | game_progress: round(100 * finished / pairs_length)}
  end

  def response_ok(data, id, result) do
    response(data, id, result)
  end
end
