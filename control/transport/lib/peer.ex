defmodule ParviTransport.Peer do
  @moduledoc false
  use GenServer
  alias ExWebRTC.{PeerConnection, SessionDescription, ICECandidate}

  def start_link(owner, initiator, ice), do: GenServer.start_link(__MODULE__, {owner, initiator, ice})
  def signal(pid, signal), do: GenServer.cast(pid, {:signal, signal})
  def send_packet(pid, packet), do: GenServer.call(pid, {:send, packet})
  def close(pid), do: GenServer.cast(pid, :close)

  def init({owner, initiator, ice}) do
    Process.flag(:trap_exit, true)
    send(self(), :start)
    {:ok, %{owner: owner, initiator: initiator, ice: ice, pc: nil,
            channel: nil, session: nil, ready: false, pending: []}}
  end
  def handle_info(:start, %{initiator: true} = s) do
    s = new_connection(%{s | session: Base.encode16(:crypto.strong_rand_bytes(16))})
    {:ok, dc} = PeerConnection.create_data_channel(s.pc, "parvi-v1")
    {:ok, offer} = PeerConnection.create_offer(s.pc)
    :ok = PeerConnection.set_local_description(s.pc, offer)
    notify(s, {:signal, description(s.session, offer)})
    {:noreply, %{s | channel: dc.ref}}
  end
  def handle_info(:start, s), do: {:noreply, s}
  def handle_info({:ex_webrtc, pc, event}, %{pc: pc} = s), do: {:noreply, rtc_event(event, s)}
  def handle_info(:stop, s), do: {:stop, :normal, s}
  def handle_info({:EXIT, pc, _}, %{pc: pc} = s) do
    notify(s, {:ready, false})
    {:stop, :normal, s}
  end
  def handle_info(_, s), do: {:noreply, s}
  def handle_call({:send, packet}, _, %{ready: true} = s) when byte_size(packet) <= 131_072 do
    :ok = PeerConnection.send_data(s.pc, s.channel, packet, :string)
    {:reply, :ok, s}
  end
  def handle_call({:send, _}, _, s), do: {:reply, {:error, :unavailable}, s}
  def handle_cast(:close, s) do
    Process.send_after(self(), :stop, 1000)
    {:noreply, s}
  end
  def handle_cast({:signal, %{"kind" => "offer", "sdp" => sdp, "session" => session}}, %{initiator: false} = s) do
    if s.pc, do: PeerConnection.close(s.pc)
    notify(s, {:ready, false})
    s = new_connection(%{s | session: session, ready: false, channel: nil})
    :ok = PeerConnection.set_remote_description(s.pc, %SessionDescription{type: :offer, sdp: sdp})
    {:ok, answer} = PeerConnection.create_answer(s.pc)
    :ok = PeerConnection.set_local_description(s.pc, answer)
    notify(s, {:signal, description(session, answer)})
    {:noreply, flush_candidates(s)}
  end
  def handle_cast({:signal, %{"kind" => "answer", "sdp" => sdp, "session" => session}}, %{initiator: true, session: session} = s) do
    :ok = PeerConnection.set_remote_description(s.pc, %SessionDescription{type: :answer, sdp: sdp})
    {:noreply, flush_candidates(s)}
  end
  def handle_cast({:signal, %{"kind" => "candidate"} = signal}, s) do
    cond do
      is_nil(s.pc) or is_nil(PeerConnection.get_remote_description(s.pc)) ->
        {:noreply, %{s | pending: Enum.take(s.pending ++ [signal], 128)}}
      signal["session"] == s.session ->
        add_candidate(s.pc, signal)
        {:noreply, s}
      true -> {:noreply, s}
    end
  end
  def handle_cast(_, s), do: {:noreply, s}
  def terminate(_, s), do: if(s.pc && Process.alive?(s.pc), do: PeerConnection.close(s.pc), else: :ok)

  defp new_connection(s) do
    {:ok, pc} = PeerConnection.start_link(ice_servers: [%{urls: s.ice}], audio_codecs: [], video_codecs: [])
    %{s | pc: pc}
  end
  defp description(session, d), do: %{"session" => session, "kind" => Atom.to_string(d.type), "sdp" => d.sdp}
  defp notify(s, event), do: send(s.owner, {:parvi_direct, self(), event})
  defp flush_candidates(s) do
    for c <- s.pending, c["session"] == s.session, do: add_candidate(s.pc, c)
    %{s | pending: []}
  end
  defp add_candidate(pc, c), do: PeerConnection.add_ice_candidate(pc,
    %ICECandidate{candidate: c["candidate"], sdp_mid: c["mid"], sdp_m_line_index: c["index"]})
  defp rtc_event({:ice_candidate, c}, s) do
    notify(s, {:signal, %{"session" => s.session, "kind" => "candidate", "candidate" => c.candidate,
                         "mid" => c.sdp_mid || "0", "index" => c.sdp_m_line_index || 0}})
    s
  end
  defp rtc_event({:data_channel, %{label: "parvi-v1", ref: ref}}, s), do: %{s | channel: ref}
  defp rtc_event({:data_channel_state_change, ref, status}, %{channel: ref} = s) do
    notify(s, {:ready, status == :open})
    %{s | ready: status == :open}
  end
  defp rtc_event({:data, ref, packet}, %{channel: ref, ready: true} = s) do
    notify(s, {:packet, packet})
    s
  end
  defp rtc_event({:connection_state_change, status}, s) when status in [:failed, :disconnected, :closed] do
    notify(s, {:ready, false})
    %{s | ready: false}
  end
  defp rtc_event(_, s), do: s
end
