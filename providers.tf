provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      Environment = "spot-lab"
      ManagedBy   = "terraform"
      Project     = var.project_name
    }
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = "spot-lab"
      ManagedBy   = "terraform"
      Project     = var.project_name
    }
  }
}
