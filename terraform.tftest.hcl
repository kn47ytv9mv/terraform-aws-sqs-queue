mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/mock-queue"
    }
  }
}

run "name_with_invalid_characters_is_rejected" {
  command = plan

  variables {
    name = "order events"
  }

  expect_failures = [var.name]
}

run "name_exceeding_eighty_characters_once_suffixed_is_rejected" {
  command = plan

  variables {
    name       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    fifo_queue = true
  }

  expect_failures = [var.name]
}

run "fifo_only_settings_on_a_standard_queue_are_rejected" {
  command = plan

  variables {
    content_based_deduplication = true
  }

  expect_failures = [var.fifo_queue]
}

run "invalid_deduplication_scope_is_rejected" {
  command = plan

  variables {
    fifo_queue          = true
    deduplication_scope = "MessageGroup"
  }

  expect_failures = [var.deduplication_scope]
}

run "invalid_fifo_throughput_limit_is_rejected" {
  command = plan

  variables {
    fifo_queue            = true
    fifo_throughput_limit = "perGroup"
  }

  expect_failures = [var.fifo_throughput_limit]
}

run "per_message_group_throughput_requires_message_group_scope" {
  command = plan

  variables {
    fifo_queue            = true
    fifo_throughput_limit = "perMessageGroup"
  }

  expect_failures = [var.fifo_throughput_limit]
}

run "visibility_timeout_beyond_twelve_hours_is_rejected" {
  command = plan

  variables {
    visibility_timeout_seconds = 86400
  }

  expect_failures = [var.visibility_timeout_seconds]
}

run "message_retention_beyond_fourteen_days_is_rejected" {
  command = plan

  variables {
    message_retention_seconds = 2592000
  }

  expect_failures = [var.message_retention_seconds]
}

run "receive_wait_time_beyond_twenty_seconds_is_rejected" {
  command = plan

  variables {
    receive_wait_time_seconds = 60
  }

  expect_failures = [var.receive_wait_time_seconds]
}

run "delay_beyond_fifteen_minutes_is_rejected" {
  command = plan

  variables {
    delay_seconds = 3600
  }

  expect_failures = [var.delay_seconds]
}

run "max_message_size_beyond_the_limit_is_rejected" {
  command = plan

  variables {
    max_message_size = 1048576
  }

  expect_failures = [var.max_message_size]
}

run "dead_letter_queue_without_a_target_is_rejected" {
  command = plan

  variables {
    enable_dead_letter_queue = true
  }

  expect_failures = [var.enable_dead_letter_queue]
}

run "dead_letter_target_without_the_switch_is_rejected" {
  command = plan

  variables {
    dead_letter_target_arn = "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
  }

  expect_failures = [var.enable_dead_letter_queue]
}

run "max_receive_count_beyond_the_limit_is_rejected" {
  command = plan

  variables {
    max_receive_count = 1001
  }

  expect_failures = [var.max_receive_count]
}

run "a_kms_key_alongside_sqs_managed_encryption_is_rejected" {
  command = plan

  variables {
    kms_master_key_id = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [var.sqs_managed_sse_enabled]
}

run "kms_data_key_reuse_period_beyond_the_limit_is_rejected" {
  command = plan

  variables {
    kms_data_key_reuse_period_seconds = 100000
  }

  expect_failures = [var.kms_data_key_reuse_period_seconds]
}

run "name_defaults_to_random_uuid" {
  command = apply

  assert {
    condition     = aws_sqs_queue.resource.name == random_uuid.resource.id
    error_message = "Leaving name unset should fall back to the generated random_uuid."
  }
}

run "standard_queue_gets_no_suffix" {
  command = plan

  variables {
    name = "order-events"
  }

  assert {
    condition     = aws_sqs_queue.resource.name == "order-events"
    error_message = "A standard queue's name should be left exactly as supplied."
  }
}

run "fifo_queue_appends_the_required_suffix" {
  command = plan

  variables {
    name       = "order-events"
    fifo_queue = true
  }

  assert {
    condition     = aws_sqs_queue.resource.name == "order-events.fifo"
    error_message = "A FIFO queue's name must end in '.fifo', which the module should append rather than making every caller type it."
  }
}

run "fifo_suffix_is_not_doubled" {
  command = plan

  variables {
    name       = "order-events.fifo"
    fifo_queue = true
  }

  assert {
    condition     = aws_sqs_queue.resource.name == "order-events.fifo"
    error_message = "A name already ending in '.fifo' should not have the suffix appended twice."
  }
}

run "encryption_is_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_sqs_queue.resource.sqs_managed_sse_enabled == true
    error_message = "A queue should be encrypted with the SQS-managed key by default rather than created unencrypted."
  }

  assert {
    condition     = aws_sqs_queue.resource.kms_master_key_id == null
    error_message = "The default encryption should cost nothing and require no key policy, which rules out a KMS key."
  }
}

run "a_kms_key_replaces_the_sqs_managed_key" {
  command = plan

  variables {
    sqs_managed_sse_enabled           = false
    kms_master_key_id                 = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    kms_data_key_reuse_period_seconds = 3600
  }

  assert {
    condition     = aws_sqs_queue.resource.kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A supplied KMS key should reach the queue, with sqs_managed_sse_enabled left unset so the provider does not reject the two as conflicting."
  }

  assert {
    condition     = aws_sqs_queue.resource.kms_data_key_reuse_period_seconds == 3600
    error_message = "The data key reuse period should reach the queue unchanged."
  }
}

run "long_polling_is_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_sqs_queue.resource.receive_wait_time_seconds == 20
    error_message = "A queue should long-poll by default, so an idle consumer is not billed for a request per loop iteration."
  }
}

run "dead_letter_queue_builds_the_redrive_policy" {
  command = plan

  variables {
    name                     = "order-events"
    enable_dead_letter_queue = true
    dead_letter_target_arn   = "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
    max_receive_count        = 3
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.resource.redrive_policy).deadLetterTargetArn == "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
    error_message = "The redrive policy should name the supplied dead-letter queue."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.resource.redrive_policy).maxReceiveCount == 3
    error_message = "The redrive policy should carry max_receive_count as maxReceiveCount."
  }
}

run "readme_registry_example" {
  command = plan

  variables {
    name                       = "order-events"
    visibility_timeout_seconds = 300
  }
}

run "readme_dead_letter_queue_example" {
  command = plan

  variables {
    name                      = "order-events-dlq"
    message_retention_seconds = 1209600
  }
}

run "readme_work_queue_example" {
  command = plan

  variables {
    name                       = "order-events"
    visibility_timeout_seconds = 300
    enable_dead_letter_queue   = true
    dead_letter_target_arn     = "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
    max_receive_count          = 3
  }
}
