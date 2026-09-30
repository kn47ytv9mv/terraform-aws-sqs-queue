variable "name" {
  default     = null
  description = "Name of the queue. A FIFO queue's name must end in '.fifo', which this module appends automatically when fifo_queue is set. If null, a unique name is generated."

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9_-]+(\\.fifo)?$", var.name))
    error_message = "A queue name may contain only alphanumeric characters, hyphens, and underscores, optionally followed by the '.fifo' suffix."
  }

  validation {
    condition     = var.name == null || length(var.fifo_queue && !endswith(var.name, ".fifo") ? "${var.name}.fifo" : var.name) <= 80
    error_message = "A queue name may be at most 80 characters, counting the '.fifo' suffix this module appends for a FIFO queue."
  }
}

variable "fifo_queue" {
  default     = false
  description = "Whether the queue delivers messages in the order they were sent and refuses duplicates within a five-minute window. A FIFO queue trades throughput for that guarantee, and it cannot be the destination of an S3 event notification."

  validation {
    condition     = var.fifo_queue || (var.content_based_deduplication == null && var.deduplication_scope == null && var.fifo_throughput_limit == null)
    error_message = "content_based_deduplication, deduplication_scope, and fifo_throughput_limit apply only to a FIFO queue. Either set fifo_queue to true or leave all three unset."
  }
}

variable "content_based_deduplication" {
  default     = null
  description = "Whether a FIFO queue derives each message's deduplication ID from a hash of its body rather than requiring the publisher to supply one. Two messages with identical bodies sent within five minutes are then treated as duplicates and the second is discarded, so leave this unset when identical payloads are legitimately distinct events. Only meaningful when fifo_queue is true."
}

variable "deduplication_scope" {
  default     = null
  description = "Whether a FIFO queue deduplicates across the whole queue ('queue') or only within each message group ('messageGroup'). Only meaningful when fifo_queue is true."

  validation {
    condition     = var.deduplication_scope == null || contains(["messageGroup", "queue"], var.deduplication_scope)
    error_message = "deduplication_scope must be 'messageGroup' or 'queue', spelled exactly as shown."
  }
}

variable "fifo_throughput_limit" {
  default     = null
  description = "Whether a FIFO queue's throughput quota applies to the queue as a whole ('perQueue') or to each message group separately ('perMessageGroup'). 'perMessageGroup' is what raises a FIFO queue past its base quota, and it requires deduplication_scope to be 'messageGroup'. Only meaningful when fifo_queue is true."

  validation {
    condition     = var.fifo_throughput_limit == null || contains(["perQueue", "perMessageGroup"], var.fifo_throughput_limit)
    error_message = "fifo_throughput_limit must be 'perQueue' or 'perMessageGroup', spelled exactly as shown."
  }

  validation {
    condition     = var.fifo_throughput_limit != "perMessageGroup" || var.deduplication_scope == "messageGroup"
    error_message = "fifo_throughput_limit of 'perMessageGroup' requires deduplication_scope to be 'messageGroup'. AWS rejects the combination otherwise."
  }
}

variable "visibility_timeout_seconds" {
  default     = null
  description = "How long a message stays hidden from other consumers after one consumer receives it. Set this above the worst-case processing time of the consumer, or a slow handler will see the same message delivered again while it is still working on the first copy. If null, AWS's own default of 30 seconds applies."

  validation {
    condition     = var.visibility_timeout_seconds == null || (var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200)
    error_message = "visibility_timeout_seconds must be between 0 and 43200, AWS's ceiling of twelve hours."
  }
}

variable "message_retention_seconds" {
  default     = null
  description = "How long an unconsumed message is kept before SQS deletes it. A dead-letter queue wants this near the 1209600-second maximum, since the point of one is to hold a failed message long enough for somebody to look at it. If null, AWS's own default of 345600 seconds applies."

  validation {
    condition     = var.message_retention_seconds == null || (var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600)
    error_message = "message_retention_seconds must be between 60 and 1209600, AWS's ceiling of fourteen days."
  }
}

variable "receive_wait_time_seconds" {
  default     = 20
  description = "How long a receive call waits for a message to arrive before returning empty. This module defaults to AWS's maximum of 20 seconds, which enables long polling: a consumer polling an idle queue is billed for one request every 20 seconds rather than as fast as it can loop, and a message arriving mid-wait is returned immediately instead of on the next poll. Set this to 0 only when a consumer genuinely needs a receive call to return without waiting."

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20, AWS's ceiling for a long-polling wait."
  }
}

variable "delay_seconds" {
  default     = null
  description = "How long every message sent to this queue is withheld before it becomes visible to consumers. If null, AWS's own default of 0 applies and messages are available immediately."

  validation {
    condition     = var.delay_seconds == null || (var.delay_seconds >= 0 && var.delay_seconds <= 900)
    error_message = "delay_seconds must be between 0 and 900, AWS's ceiling of fifteen minutes."
  }
}

variable "max_message_size" {
  default     = null
  description = "Largest message body the queue accepts, in bytes. Lowering it rejects an oversized payload at send time rather than letting it through. If null, AWS's own default and maximum of 262144 bytes applies."

  validation {
    condition     = var.max_message_size == null || (var.max_message_size >= 1024 && var.max_message_size <= 262144)
    error_message = "max_message_size must be between 1024 and 262144 bytes."
  }
}

variable "enable_dead_letter_queue" {
  default     = false
  description = "Whether messages this queue's consumers repeatedly fail to process are moved to the queue named by dead_letter_target_arn. This is a separate switch from that ARN because the ARN is usually another module's output, which Terraform does not know at plan time, while a boolean the caller writes literally always is."

  validation {
    condition     = !var.enable_dead_letter_queue || var.dead_letter_target_arn != null
    error_message = "enable_dead_letter_queue requires dead_letter_target_arn, the ARN of the queue that receives the failed messages."
  }

  validation {
    condition     = var.enable_dead_letter_queue || var.dead_letter_target_arn == null
    error_message = "dead_letter_target_arn has no effect unless enable_dead_letter_queue is true. Set the boolean or drop the ARN."
  }
}

variable "dead_letter_target_arn" {
  default     = null
  description = "ARN of the queue receiving messages this queue's consumers failed to process max_receive_count times. A FIFO queue may only dead-letter to another FIFO queue, and a standard queue only to another standard queue. Takes effect only when enable_dead_letter_queue is true."
}

variable "max_receive_count" {
  default     = 5
  description = "How many times a message may be received and left unprocessed before it is moved to the dead-letter queue. This counts receives rather than elapsed time: a consumer that crashes before deleting a message burns one attempt each time the visibility timeout expires. Only meaningful when enable_dead_letter_queue is true."

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "redrive_allow_policy" {
  default     = null
  description = "JSON policy naming which source queues may use this queue as their dead-letter queue, for a queue serving that role. Set redrivePermission to 'denyAll', 'allowAll', or 'byQueue' with a sourceQueueArns list. If null, AWS allows any queue in the same account and region. Read this module's README before naming a source queue created by another call of this module."
}

variable "sqs_managed_sse_enabled" {
  default     = true
  description = "Whether messages are encrypted at rest with a key SQS owns and manages, at no additional cost and with no key policy to maintain. This module enables it by default so that a queue is never left unencrypted by omission. Set it to false when supplying kms_master_key_id, because SQS accepts one form of encryption at a time."

  validation {
    condition     = !var.sqs_managed_sse_enabled || var.kms_master_key_id == null
    error_message = "Set sqs_managed_sse_enabled to false when supplying kms_master_key_id. A queue is encrypted either by an SQS-owned key or by a KMS key, never by both."
  }
}

variable "kms_master_key_id" {
  default     = null
  description = "KMS key encrypting messages at rest, in place of the SQS-owned key. Supply a customer managed key from terraform-aws-kms-key when the queue's encryption needs an auditable key policy, rotation under your control, or cross-account access. A key policy that does not grant the sending service kms:GenerateDataKey and kms:Decrypt makes every send fail, so a queue receiving events from S3, SNS, or EventBridge needs those principals in the policy."
}

variable "kms_data_key_reuse_period_seconds" {
  default     = null
  description = "How long SQS reuses a KMS data key before calling KMS again. A longer period means fewer KMS requests to pay for and a wider window in which a revoked key still decrypts. Only meaningful when kms_master_key_id is set. If null, AWS's own default of 300 seconds applies."

  validation {
    condition     = var.kms_data_key_reuse_period_seconds == null || (var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400)
    error_message = "kms_data_key_reuse_period_seconds must be between 60 and 86400."
  }
}

variable "policy" {
  default     = null
  description = "JSON access policy controlling who may send to and receive from the queue. If null, only the owning account has access, which is what a queue consumed by a role in the same account needs. A queue receiving events from another AWS service requires a statement granting that service's principal sqs:SendMessage, scoped with an aws:SourceArn condition so the grant does not extend to every caller of that service."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the queue."
}
