locals {
  base_name = coalesce(var.name, random_uuid.resource.id)
  name      = var.fifo_queue && !endswith(local.base_name, ".fifo") ? "${local.base_name}.fifo" : local.base_name

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = var.dead_letter_target_arn
    maxReceiveCount     = var.max_receive_count
  }) : null
}

resource "random_uuid" "resource" {}

resource "aws_sqs_queue" "resource" {
  name = local.name

  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.content_based_deduplication
  deduplication_scope         = var.deduplication_scope
  fifo_throughput_limit       = var.fifo_throughput_limit

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size

  redrive_policy       = local.redrive_policy
  redrive_allow_policy = var.redrive_allow_policy

  sqs_managed_sse_enabled           = var.sqs_managed_sse_enabled ? true : null
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds

  policy = var.policy

  tags = var.tags
}

output "id" {
  description = "The ID of the queue, which is its URL."
  value       = aws_sqs_queue.resource.id
}

output "arn" {
  description = "The ARN of the queue. Feed this into terraform-aws-lambda-function's dead_letter_target_arn, or into another call of this module's dead_letter_target_arn."
  value       = aws_sqs_queue.resource.arn
}

output "name" {
  description = "The name of the queue, including the '.fifo' suffix when fifo_queue is set."
  value       = aws_sqs_queue.resource.name
}

output "url" {
  description = "The URL of the queue. Every SQS call that sends, receives, or deletes a message identifies the queue by this URL rather than by its ARN."
  value       = aws_sqs_queue.resource.url
}
