# terraform-aws-sqs-queue

Terraform module for an SQS queue — the buffer that lets a producer keep
working when its consumer is slow, down, or scaling up, and the
dead-letter destination that keeps a message nobody could process from
disappearing.

## Cost

SQS bills per request, where a request is a send, receive, or delete
call and every 64 KB of payload counts as one additional request. A
consumer that polls an empty queue in a tight loop therefore bills for
every empty response it gets, which is why this module enables long
polling by default. FIFO queues are billed at a higher per-request rate
than standard queues. Messages held on a queue cost nothing to store,
but a queue encrypted with a customer managed key bills for the KMS
requests SQS makes on its behalf. See AWS's
[SQS pricing](https://aws.amazon.com/sqs/pricing/) page for current
rates.

## Design

SQS's access policy and its two redrive policies are configured on the
queue itself, not split into separate modules. The AWS provider offers
`aws_sqs_queue_policy`, `aws_sqs_queue_redrive_policy`, and
`aws_sqs_queue_redrive_allow_policy` as standalone resources, but each
one writes a single attribute that `aws_sqs_queue` already carries.
Neither condition for splitting is met: there is at most one of each per
queue rather than a heterogeneous set of instances, and nothing outside
the module can reference one, because the only identifier a standalone
policy resource exposes is the queue URL this module already outputs.
They are therefore set inline as attributes, which also keeps one
queue's configuration at one address in state rather than four.

### Dead-letter queues

This module is both halves of a dead-letter pairing. A queue created
here serves as the dead-letter target for another call of the same
module, and its `arn` output is what
[`terraform-aws-lambda-function`](https://github.com/kn47ytv9mv/terraform-aws-lambda-function)
expects for its own `dead_letter_target_arn`.

`enable_dead_letter_queue` is a separate boolean from
`dead_letter_target_arn` rather than the module inferring the feature
from a non-null ARN. The ARN is normally another module's output, and
Terraform does not know an output's value while it is building the plan,
so any behavior gated on whether that ARN is null fails on exactly the
composition the module exists to support. A boolean the caller writes
literally is always known at plan time. Setting one without the other is
rejected in both directions rather than silently ignored.

`max_receive_count` counts receives, not failures the consumer reported.
A consumer that crashes, times out, or is killed mid-processing never
deletes the message, so the visibility timeout expires and the message
is delivered again, burning one attempt each time. Setting
`visibility_timeout_seconds` below the consumer's worst-case processing
time therefore drives messages to the dead-letter queue while they are
still being handled successfully.

A dead-letter queue wants a long `message_retention_seconds` — the
maximum of 1209600 seconds is fourteen days — because its purpose is to
hold a failed message until somebody investigates. Retention is measured
from when the message was first sent, not from when it was moved, so a
short retention on the dead-letter queue can delete the evidence before
anyone sees it.

`redrive_allow_policy` restricts which source queues may use a queue as
their dead-letter target. Leave it unset for the common case: AWS's
default permits any queue in the same account and region, which is
already the trust boundary a single Terraform configuration works
within. When it is set to `byQueue`, write the source queue's ARN rather
than threading it back from the source module's `arn` output — two calls
of this module that each reference the other's output form a dependency
cycle Terraform rejects before it plans anything.

### Encryption

`sqs_managed_sse_enabled` defaults to true, which encrypts messages at
rest with a key SQS owns. That default is deliberate: the argument is
optional, so a module that passed it through untouched would hand an
unencrypted queue to every caller who did not think about encryption.
The SQS-managed key costs nothing and has no key policy to maintain,
which leaves no reason to make that the caller's problem.

Supply `kms_master_key_id` instead when the queue's encryption needs an
auditable key policy, rotation under your control, or cross-account
access — a customer managed key from
[`terraform-aws-kms-key`](https://github.com/kn47ytv9mv/terraform-aws-kms-key)
serves all three. Set `sqs_managed_sse_enabled` to false in the same
call, because SQS accepts one form of encryption at a time and this
module rejects the pair rather than quietly dropping one.

A customer managed key shifts the burden of authorizing senders onto the
key policy. A queue receiving events from S3, SNS, or EventBridge needs
that service's principal granted `kms:GenerateDataKey` and
`kms:Decrypt`, or every send fails with an access-denied error that
names the key rather than the queue.

### FIFO queues

A FIFO queue delivers messages in the order they were sent and discards
a duplicate sent within five minutes of the original, at the cost of
throughput and a higher per-request price. AWS requires its name to end
in `.fifo`; this module appends the suffix when `fifo_queue` is set
rather than making every caller remember it, and does not double it on a
name that already carries it. The 80-character name limit counts the
suffix, which the module validates against the name it will actually
create.

`fifo_throughput_limit` set to `perMessageGroup` is what raises a FIFO
queue above its base throughput quota, and AWS accepts it only alongside
`deduplication_scope` of `messageGroup`. That pairing is validated here
so the rejection arrives at plan time. `content_based_deduplication`
derives each message's deduplication ID from a hash of its body, which
means two legitimately distinct events carrying identical payloads
collapse into one — leave it unset when that is possible.

A FIFO queue may only dead-letter to another FIFO queue, and a standard
queue only to another standard queue. A FIFO queue also cannot be the
destination of an S3 event notification.

### What this module does not cover

The event source mapping that makes a consumer poll this queue is not
created here, because that resource belongs to the consumer rather than
to the queue. Nothing here subscribes the queue to an SNS topic either —
that subscription belongs to the topic, and
[`terraform-aws-sns-topic`](https://github.com/kn47ytv9mv/terraform-aws-sns-topic)
takes the queue ARN as an `sqs` subscription endpoint.

## Usage

```hcl
module "order_events" {
  source = "kn47ytv9mv/sqs-queue/aws"

  name                       = "order-events"
  visibility_timeout_seconds = 300
}
```

Or directly from this repository, pairing a work queue with the
dead-letter queue that catches what it cannot process:

```hcl
module "order_events_dlq" {
  source = "github.com/kn47ytv9mv/terraform-aws-sqs-queue"

  name                      = "order-events-dlq"
  message_retention_seconds = 1209600
}

module "order_events" {
  source = "github.com/kn47ytv9mv/terraform-aws-sqs-queue"

  name                       = "order-events"
  visibility_timeout_seconds = 300

  enable_dead_letter_queue = true
  dead_letter_target_arn   = module.order_events_dlq.arn
  max_receive_count        = 3
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| name | Name of the queue. A FIFO queue's `.fifo` suffix is appended automatically. If null, a unique name is generated. | `null` | no |
| fifo_queue | Whether the queue preserves send order and discards duplicates. Cannot be the destination of an S3 event notification. | `false` | no |
| content_based_deduplication | Whether a FIFO queue derives deduplication IDs from a hash of the message body. | `null` | no |
| deduplication_scope | Whether a FIFO queue deduplicates across the queue (`'queue'`) or within each message group (`'messageGroup'`). | `null` | no |
| fifo_throughput_limit | Whether a FIFO queue's throughput quota applies per queue (`'perQueue'`) or per message group (`'perMessageGroup'`). | `null` | no |
| visibility_timeout_seconds | How long a received message stays hidden from other consumers. Set it above the consumer's worst-case processing time — see Design. | `null` | no |
| message_retention_seconds | How long an unconsumed message is kept, from 60 to 1209600 seconds. | `null` | no |
| receive_wait_time_seconds | How long a receive call waits before returning empty. Defaults to long polling — see Cost. | `20` | no |
| delay_seconds | How long every message is withheld before becoming visible, up to 900 seconds. | `null` | no |
| max_message_size | Largest message body the queue accepts, from 1024 to 262144 bytes. | `null` | no |
| enable_dead_letter_queue | Whether repeatedly unprocessed messages move to `dead_letter_target_arn`. A separate switch from the ARN — see Design. | `false` | no |
| dead_letter_target_arn | ARN of the queue receiving messages this queue's consumers failed to process. | `null` | no |
| max_receive_count | How many receives a message survives before being dead-lettered. | `5` | no |
| redrive_allow_policy | JSON policy naming which source queues may dead-letter to this queue. | `null` | no |
| sqs_managed_sse_enabled | Whether messages are encrypted at rest with an SQS-owned key. Set to false when supplying `kms_master_key_id`. | `true` | no |
| kms_master_key_id | KMS key encrypting messages at rest, in place of the SQS-owned key. | `null` | no |
| kms_data_key_reuse_period_seconds | How long SQS reuses a KMS data key, from 60 to 86400 seconds. | `null` | no |
| policy | JSON access policy controlling who may send to and receive from the queue. | `null` | no |
| tags | A map of tags to assign to the queue. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the queue, which is its URL. |
| arn | The ARN of the queue. Feed this into `terraform-aws-lambda-function`'s `dead_letter_target_arn`, or into another call of this module's `dead_letter_target_arn`. |
| name | The name of the queue, including the `.fifo` suffix when `fifo_queue` is set. |
| url | The URL of the queue, which is how every SQS message call identifies it rather than by ARN. |

## License

MIT — see [LICENSE.md](LICENSE.md).
