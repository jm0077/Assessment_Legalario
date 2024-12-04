provider "aws" {
  region = "us-east-1"
}

# Creación de VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Main VPC"
  }
}

# Creación de subredes públicas
resource "aws_subnet" "public_1" {
  vpc_id             = aws_vpc.main.id
  cidr_block         = "10.0.1.0/24"
  availability_zone  = "us-east-1a"
  tags = {
    Name = "Public Subnet 1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id             = aws_vpc.main.id
  cidr_block         = "10.0.2.0/24"
  availability_zone  = "us-east-1b"
  tags = {
    Name = "Public Subnet 2"
  }
}

resource "aws_subnet" "public_3" {
  vpc_id             = aws_vpc.main.id
  cidr_block         = "10.0.3.0/24"
  availability_zone  = "us-east-1c"
  tags = {
    Name = "Public Subnet 3"
  }
}

# Creación de Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "Main IGW"
  }
}

# Creación de la tabla de enrutamiento
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "Public Route Table"
  }
}

# Asociaciones de subredes con la tabla de enrutamiento
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_3" {
  subnet_id      = aws_subnet.public_3.id
  route_table_id = aws_route_table.public.id
}

# Creación de grupo de seguridad
resource "aws_security_group" "allow_http" {
  name   = "Allow HTTP"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# Creación de Load Balancer
resource "aws_lb" "main" {
  name               = "my-nginx-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id, aws_subnet.public_3.id]
}

# Creación de Target Group
resource "aws_lb_target_group" "main" {
  name        = "my-nginx-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_lb_target_group" "green" {
  name        = "my-nginx-green-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# Listener del Load Balancer
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Creación del repositorio ECR para la app
resource "aws_ecr_repository" "nginx_app" {
  name                 = "my-nginx-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Creación del ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "my-nginx-prod-cluster"
}

# IAM Role para ejecución de tareas de ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Adjuntar política de ejecución de tareas
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role para tareas ECS
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Adjuntar permisos específicos para el rol de tarea
resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "ecs-task-role-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Definición de la tarea ECS
resource "aws_ecs_task_definition" "main" {
  family                   = "nginx-task-family"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode            = "awsvpc"
  cpu                      = "256"  # Asigna 256 unidades de CPU
  memory                   = "512"  # Asigna 512 MB de memoria
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode([{
    name      = "nginx-container"
    image     = "${aws_ecr_repository.nginx_app.repository_url}:latest"
    cpu       = 256  # CPU para el contenedor específico
    memory    = 512  # Memoria para el contenedor específico
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
	logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/my-nginx-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# Creación del servicio ECS
resource "aws_ecs_service" "main" {
  name            = "my-nginx-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "nginx-container"
    container_port   = 80
  }

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id, aws_subnet.public_3.id]  # Múltiples subredes
    security_groups = [aws_security_group.allow_http.id]
	assign_public_ip = true
  }

  depends_on = [aws_lb_listener.main]
}

# Outputs para usar en la definición de tareas
output "task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "task_role_arn" {
  value = aws_iam_role.ecs_task_role.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "load_balancer_arn" {
  value = aws_lb.main.arn
}

output "load_balancer_listener_arn" {
  value = aws_lb_listener.main.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.main.arn
}

output "public_subnet_ids" {
  value = [
    aws_subnet.public_1.id, 
    aws_subnet.public_2.id, 
    aws_subnet.public_3.id
  ]
}

output "security_group_id" {
  value       = aws_security_group.allow_http.id
  description = "El ID del grupo de seguridad para permitir tráfico HTTP."
}

output "green_target_group_arn" {
  value       = aws_lb_target_group.green.arn
  description = "The ARN of the green target group for Blue-Green deployments"
}