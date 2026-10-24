resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = aws_subnet.isolated_db[*].id

  tags = {
    Name = "${var.project_name}-aurora-subnet-group"
  }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.project_name}-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.4" # Or any recent stable supporting Serverless v2

  database_name   = "spotlabdb"
  master_username = "postgres"
  master_password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.db.id]

  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.5
  }

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "${var.project_name}-aurora-cluster"
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.project_name}-aurora-writer"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  availability_zone   = "ap-northeast-1a"
  publicly_accessible = false

  db_subnet_group_name = aws_db_subnet_group.aurora.name
  apply_immediately    = true

  tags = {
    Name = "${var.project_name}-aurora-writer"
  }
}

resource "aws_rds_cluster_instance" "reader" {
  identifier          = "${var.project_name}-aurora-reader"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  availability_zone   = "ap-northeast-1c"
  publicly_accessible = false

  db_subnet_group_name = aws_db_subnet_group.aurora.name
  apply_immediately    = true
  promotion_tier       = 1

  tags = {
    Name = "${var.project_name}-aurora-reader"
  }
}
