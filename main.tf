variable "use_case" {
  default = {
    name  = "rds-postgres-password-autorotate"
    owner = "John Ajera"
  }
}

variable "region" {
  description = "AWS region"
  default = {
    default = "ap-southeast-1"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_resourcegroups_group" "example" {
  name        = "tf-${var.use_case.name}-rg-example-${random_string.suffix.result}"
  description = "Resource group for example resources"

  resource_query {
    query = <<JSON
    {
      "ResourceTypeFilters": [
        "AWS::AllSupported"
      ],
      "TagFilters": [
        {
          "Key": "Owner",
          "Values": ["${var.use_case.owner}"]
        },
        {
          "Key": "UseCase",
          "Values": ["${var.use_case.name}"]
        }
      ]
    }
    JSON
  }

  tags = {
    Name    = "tf-${var.use_case.name}-rg-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "tf-${var.use_case.name}-vpc-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_subnet" "example" {
  count             = 2
  vpc_id            = aws_vpc.example.id
  cidr_block        = cidrsubnet(aws_vpc.example.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name    = "tf-${var.use_case.name}-subnet-example-${count.index}-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_db_subnet_group" "example" {
  subnet_ids = [for s in aws_subnet.example : s.id]

  tags = {
    Name    = "tf-${var.use_case.name}-db-subnet-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_security_group" "example" {
  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.example.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.example.cidr_block]
  }

  timeouts {
    delete = "30m"
  }

  tags = {
    Name    = "tf-${var.use_case.name}-sg-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.example.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.example[0].id]
  security_group_ids  = [aws_security_group.example.id]

  tags = {
    Name    = "tf-${var.use_case.name}-vpce-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "random_password" "example" {
  length           = 40
  special          = true
  min_special      = 5
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "example" {
  name        = "tf-${var.use_case.name}-secretsmanager-example-${random_string.suffix.result}"
  description = "RDS database admin credentials for tf-${var.use_case.name}-rds-cluster-example-${random_string.suffix.result}"

  tags = {
    Name    = "tf-${var.use_case.name}-secretsmanager-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

data "aws_rds_engine_version" "latest_postgres" {
  engine                 = "postgres"
  parameter_group_family = "postgres16"
  preferred_versions     = []
  default_only           = true
}

resource "aws_db_instance" "example" {
  identifier = "tf-${var.use_case.name}-postgres-example-${random_string.suffix.result}"
  allocated_storage    = 5
  storage_type         = "gp2"
  db_name              = "postgresdb"
  db_subnet_group_name = aws_db_subnet_group.example.name
  engine               = "postgres"
  engine_version       = data.aws_rds_engine_version.latest_postgres.version
  instance_class       = "db.t3.micro"
  username             = "dbadmin"
  password             = random_password.example.result
  skip_final_snapshot  = true

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]

  tags = {
    Name    = "tf-${var.use_case.name}-rds-db-instance-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_secretsmanager_secret_version" "example" {
  secret_id = aws_secretsmanager_secret.example.id
  secret_string = jsonencode(
    {
      username = aws_db_instance.example.username
      password = aws_db_instance.example.password
      engine   = aws_db_instance.example.engine
      host     = aws_db_instance.example.endpoint
    }
  )
}

resource "aws_iam_role" "rotator" {
  name = "tf-iam-role-rotator-example-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "tf-iam-role-rotator-example-${random_string.suffix.result}"
    Owner   = var.use_case.owner
    UseCase = var.use_case.name
  }
}

resource "aws_iam_role_policy" "rotation_single_user_policy_0" {
  name = "SecretsManagerRDSPostgreSQLRotationSingleUserRolePolicy0"
  role = aws_iam_role.rotator.id
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DetachNetworkInterface"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_lambda_function" "example" {
  function_name = "tf-${var.use_case.name}-lambda-example-${random_string.suffix.result}"
  description   = "Rotates a Secrets Manager secret for Amazon RDS PostgreSQL credentials using the single user rotation strategy."
  role          = aws_iam_role.rotator.arn

  runtime     = "python3.9"
  handler     = "lambda_function.lambda_handler"
  memory_size = 128
  timeout     = 30

  package_type = "Zip"
  filename     = "${path.module}/external/lambda/lambda_function.zip"

  environment {
    variables = {
      EXCLUDE_CHARACTERS         = "/@\"'\\",
      EXCLUDE_LOWERCASE          = "false",
      EXCLUDE_NUMBERS            = "false",
      EXCLUDE_PUNCTUATION        = "false",
      EXCLUDE_UPPERCASE          = "false",
      PASSWORD_LENGTH            = "32",
      REQUIRE_EACH_INCLUDED_TYPE = "true",
      SECRETS_MANAGER_ENDPOINT   = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  ephemeral_storage {
    size = 512
  }

  vpc_config {
    subnet_ids         = [aws_subnet.example[0].id]
    security_group_ids = [aws_security_group.example.id]
  }

  tags = {
    SecretsManagerLambda             = "Rotation"
    Name                             = "tf-${var.use_case.name}-rds-cluster-example-${random_string.suffix.result}"
    Owner                            = var.use_case.owner
    UseCase                          = var.use_case.name
  }
}

resource "aws_iam_role_policy_attachment" "basic_execution_role" {
  role       = aws_iam_role.rotator.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc_access_execution_role" {
  role       = aws_iam_role.rotator.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_secretsmanager_secret_rotation" "rotation" {
  secret_id           = aws_secretsmanager_secret_version.example.secret_id
  rotation_lambda_arn = aws_lambda_function.example.arn

  rotation_rules {
    schedule_expression = "rate(4 hours)"
  }
}

resource "aws_iam_role_policy" "rotation_single_user_policy_1" {
  name = "SecretsManagerRDSPostgreSQLRotationSingleUserRolePolicy1"
  role = aws_iam_role.rotator.id
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ],
        "Condition" : {
          "StringEquals" : {
            "secretsmanager:resource/AllowRotationLambdaArn" : aws_secretsmanager_secret_rotation.rotation.rotation_lambda_arn
          }
        },
        "Effect" : "Allow",
        "Resource" : "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*"
      },
      {
        "Action" : [
          "secretsmanager:GetRandomPassword"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_lambda_function_event_invoke_config" "example" {
  function_name = aws_lambda_function.example.function_name

  maximum_event_age_in_seconds = 21600
  maximum_retry_attempts       = 2
}

resource "aws_lambda_permission" "example" {
  statement_id   = "AllowSecretRotation"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.example.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}
