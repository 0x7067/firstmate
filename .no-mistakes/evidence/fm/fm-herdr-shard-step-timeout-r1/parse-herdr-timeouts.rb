#!/usr/bin/env ruby
# Semantic model of the Herdr CI hang-tripwire contract.
# Parses GitHub Actions workflow YAML (the real machine-consumed artifact)
# into a typed job/step model. Does not grep source text.
require "yaml"
require "json"

path = ARGV.fetch(0)
doc = YAML.load_file(path)
job = doc.fetch("jobs").fetch("tests-herdr")
steps = job.fetch("steps")
family = steps.find { |s| s.is_a?(Hash) && s["name"] == "Run real-Herdr family (serial, required)" }
cleanup = steps.find { |s| s.is_a?(Hash) && s["name"] == "Cleanup job-owned Herdr lab sessions" }
upload = steps.find { |s| s.is_a?(Hash) && s["name"] == "Upload Herdr timing and diagnostics" }

model = {
  "job" => "tests-herdr",
  "job_timeout_minutes" => job["timeout-minutes"],
  "family_run_step" => family && {
    "name" => family["name"],
    "timeout_minutes" => family["timeout-minutes"],
    "has_timeout" => family.key?("timeout-minutes"),
  },
  "cleanup_step" => cleanup && {
    "name" => cleanup["name"],
    "if" => cleanup["if"],
    "runs_after_step_failure_or_cancel" => cleanup["if"].to_s.include?("always()"),
  },
  "upload_step" => upload && {
    "name" => upload["name"],
    "if" => upload["if"],
    "runs_after_step_failure_or_cancel" => upload["if"].to_s.include?("always()"),
  },
}

family_timeout = family && family["timeout-minutes"]
job_timeout = job["timeout-minutes"]
model["contract"] = {
  "job_backstop_minutes" => job_timeout,
  "step_tripwire_minutes" => family_timeout,
  "step_is_tighter_than_job" => !family_timeout.nil? && !job_timeout.nil? && family_timeout < job_timeout,
  "healthy_runs_about_minutes" => 7,
  "step_above_healthy_runtime" => !family_timeout.nil? && family_timeout > 7,
  "step_far_below_job_cap" => !family_timeout.nil? && !job_timeout.nil? && family_timeout <= (job_timeout / 2),
  "cleanup_and_upload_survive_step_timeout" =>
    model.dig("cleanup_step", "runs_after_step_failure_or_cancel") == true &&
    model.dig("upload_step", "runs_after_step_failure_or_cancel") == true,
}

puts JSON.pretty_generate(model)
