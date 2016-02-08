defmodule Inco do
  use Application

  def start(_type, _args) do
    Inco.Supervisor.start_link
  end
end

defmodule Inco.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      worker(Inco.Slacker, [System.get_env("SLACK_TOKEN")])
    ]

    supervise(children, strategy: :one_for_one)
  end
end

defmodule Inco.Slacker do
  use Slacker
  use Slacker.Matcher

  match "dev api git status", :git_status
  match "dev api deploy", :api_deploy

  def git_status(tars, msg) do
    dir = System.get_env("API_DIR")
    case System.cmd("git", ["status"], cd: dir) do
      {res, 0} ->
        say(tars, msg["channel"], res)
      {_res, code} ->
        raise RuntimeError, "`git pull` failed with code #{code}"
    end
  end

  def api_deploy(tars, msg) do
    dir = System.get_env("API_DIR")
    pfile = System.get_env("UNICORN_PFILE")
    env = System.get_env("ELIXIR_ENV")
    case git_pull(dir) do
      {:ok, res} ->
        {:ok, res}
      {res, code} ->
        say(tars, msg["channel"], "#{res}\n git pull failed with code #{code}")
    end
    case kill_unicorn(pfile) do
      {:ok, res} ->
        {:ok, res}
      {res, code} ->
        say(tars, msg["channel"], "#{res}\n kill process failed with code #{code}")
    end
    case start_unicorn(env, dir) do
      {:ok, res} ->
        {:ok, res}
      {res, code} ->
        say(tars, msg["channel"], "#{res}\n start unicorn failed with code #{code}")
    end
    say(tars, msg["channel"], "api deploy done. unicorn started!")
  end

  def git_pull(dir) do
    case System.cmd("git", ["pull"], cd: dir) do
      {res, 0} ->
        {:ok, res}
      {res, code} ->
        {res, code}
    end
  end

  def kill_unicorn(pfile) do
    {pid, 0} = System.cmd("cat", ["#{pfile}"])
    case System.cmd("kill", ["#{String.rstrip(pid)}"]) do
      {res, 0} ->
        {:ok, res}
      {res, code} ->
        {res, code}
    end
  end

  def start_unicorn(env, dir) do
    case System.cmd("bundle", ["exec", "unicorn -c config/unicorn.rb -E #{env} -D"], cd: dir) do
      {res, 0} ->
        {:ok, res}
      {res, code} ->
        {res, code}
    end
  end
end
