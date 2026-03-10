require "fugit"

class ManageSchedule < RubyLLM::Tool
  description "Create, list, or cancel scheduled tasks. Use cron expressions for recurring schedules."

  param :action, desc: "One of: create, list, cancel"
  param :prompt, desc: "What Erin should do when the schedule fires (for create)", required: false
  param :cron, desc: "Cron expression for recurring schedules, e.g. '0 8 * * *' for daily at 8am (for create)", required: false
  param :run_at, desc: "ISO 8601 datetime for one-off schedules, e.g. '2026-03-10T09:00:00' (for create)", required: false
  param :channel, desc: "Channel to deliver result to: 'telegram' or 'console' (defaults to current channel)", required: false
  param :schedule_id, desc: "Schedule ID to cancel (for cancel)", required: false

  def initialize(user:, channel:)
    @user = user
    @channel = channel
  end

  def execute(action:, prompt: nil, cron: nil, run_at: nil, channel: nil, schedule_id: nil)
    case action
    when "create" then create(prompt, cron, run_at, channel)
    when "list" then list
    when "cancel" then cancel(schedule_id)
    else "Unknown action: #{action}. Use create, list, or cancel."
    end
  end

  private

  def create(prompt, cron, run_at, channel)
    return "A prompt is required." unless prompt

    target_channel = channel || @channel

    if cron
      parsed = Fugit::Cron.parse(cron)
      return "Invalid cron expression: #{cron}" unless parsed
      next_run = parsed.next_time.to_t
    elsif run_at
      next_run = Time.parse(run_at)
      return "Time must be in the future." if next_run <= Time.now
    else
      return "Either cron (recurring) or run_at (one-off) is required."
    end

    schedule = @user.schedules.create!(
      prompt: prompt,
      cron: cron,
      channel: target_channel,
      next_run_at: next_run
    )

    if cron
      "Schedule ##{schedule.id} created. Next run: #{next_run.strftime('%Y-%m-%d %H:%M')}. Recurring: #{cron}."
    else
      "Schedule ##{schedule.id} created. Will run at: #{next_run.strftime('%Y-%m-%d %H:%M')}."
    end
  end

  def list
    schedules = @user.schedules.where(active: true).order(:next_run_at)
    return "No active schedules." if schedules.empty?

    lines = schedules.map do |s|
      type = s.cron ? "recurring (#{s.cron})" : "one-off"
      "##{s.id} | #{type} | next: #{s.next_run_at.strftime('%Y-%m-%d %H:%M')} | #{s.channel} | #{s.prompt}"
    end

    lines.join("\n")
  end

  def cancel(schedule_id)
    return "A schedule_id is required." unless schedule_id

    schedule = @user.schedules.find_by(id: schedule_id, active: true)
    return "Schedule ##{schedule_id} not found or already inactive." unless schedule

    schedule.update!(active: false)
    "Schedule ##{schedule_id} cancelled."
  end
end
