locals {
  sleeps = [for v in range(1, 1000) : "sleep-${v}"]
}

data "local_file" "randomness" {
  filename = "${path.module}/randomness"
}

resource "time_sleep" "wait_1ms" {
  for_each = toset(local.sleeps)

  depends_on = [data.local_file.randomness]

  create_duration = "1ms"
}

# This resource will create (at least) 1ms after null_resource.previous
resource "null_resource" "next" {
  depends_on = [time_sleep.wait_1ms]
}
