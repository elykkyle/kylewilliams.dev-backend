

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.6.2"
    }
  }
  cloud {
    organization = "elykkyle"
    workspaces {
      name = "kylewilliamsdev-backend"
    }
  }
}

provider "aws" {
  region  = "us-east-2"
  # profile = "dev"
}

# ********** DYNAMODB TABLE **********

resource "aws_dynamodb_table" "stats-db" {
  name           = "cloud-resume-stats"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "stats"

  attribute {
    name = "stats"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "view-count" {
  table_name = aws_dynamodb_table.stats-db.name
  hash_key   = aws_dynamodb_table.stats-db.hash_key

    item = <<ITEM
  {
      "stats": {"S": "viewCount"},
      "viewCount": {"N": "0"}
  }
  ITEM
}

resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "table/${aws_dynamodb_table.stats-db.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }

    target_value = 70
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "table/${aws_dynamodb_table.stats-db.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_write_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }

    target_value = 70
  }
}

# ********** LAMBDA FUNCTION **********
# TODO: logging.

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_execution" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Scan",
      "dynamodb:UpdateItem"
    ]
    resources = [aws_dynamodb_table.stats-db.arn]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_role_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_policy" "lambda_execution" {
  name        = "lambda_execution"
  description = "IAM policy for lambda to update DynamoDB table"
  policy      = data.aws_iam_policy_document.lambda_execution.json
}

resource "aws_iam_role_policy_attachment" "lambda_execution" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_execution.arn
}

data "archive_file" "visitor_count" {
  type        = "zip"
  source_file = "${path.root}/../lambda/src/app.py"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "visitor_count" {
  filename      = "lambda_function_payload.zip"
  function_name = "increment_visitor_count"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "app.lambda_handler"

  source_code_hash = data.archive_file.visitor_count.output_base64sha256

  runtime = "python3.10"
}

resource "aws_lambda_permission" "visitor_count" {
  statement_id  = "AllowVisitorCountAPIInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_count.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_count.execution_arn}/*"
}

# ********* API Gateway **********

resource "aws_apigatewayv2_api" "visitor_count" {
  name          = "visitor-count-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "visitor_count" {
  api_id           = aws_apigatewayv2_api.visitor_count.id
  integration_type = "AWS_PROXY"

  description        = "Lambda visitor count."
  integration_method = "POST"
  integration_uri    = aws_lambda_function.visitor_count.invoke_arn
}

resource "aws_apigatewayv2_route" "visitor_count" {
  api_id    = aws_apigatewayv2_api.visitor_count.id
  route_key = "GET /visitorCount"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_count.id}"
}

resource "aws_apigatewayv2_stage" "visitor_count" {
  api_id      = aws_apigatewayv2_api.visitor_count.id
  name        = "v1"
  auto_deploy = "true"
  route_settings {
    route_key              = aws_apigatewayv2_route.visitor_count.route_key
    throttling_burst_limit = "50"
    throttling_rate_limit  = "25"
  }
}

output "invoke_url" {
  value = aws_apigatewayv2_stage.visitor_count.invoke_url
}