bucket         = "roboshop-terraform-state-files"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "roboshop-terraform-lock-files"
encrypt        = true