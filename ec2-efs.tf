
provider "aws" {
  region          = "ap-south-1"
  profile         = "check1"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "myvpc"
  }
}

resource "aws_subnet" "pub-sub" {
  vpc_id     = "${aws_vpc.myvpc.id}"
  cidr_block = "10.0.0.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "pub-sub"  
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.myvpc.id}"
  tags = {
    Name = "igw"
  }  
} 

resource "aws_route_table" "my-rt" {
  vpc_id = aws_vpc.myvpc.id

   tags = {
    Name = "route_table"
  }
}

resource "aws_route_table_association" "my-assoc" {
  subnet_id      = aws_subnet.pub-sub.id
  route_table_id = aws_route_table.my-rt.id
}

resource "aws_route" "my-route" {
  route_table_id = aws_route_table.my-rt.id
  destination_cidr_block ="0.0.0.0/0"
  gateway_id     = aws_internet_gateway.igw.id
} 






variable "x" {
  type = string
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDYDiGssqInIpqspHrMlS3kw0itcz51Ve0DP015IWXGvxmOe/4fffIsx0S1+utUDPgNusfa+1tk0vJ5HqGN4/dWG8iYkXCAFJoHmmX8ABfQ+IUsAifPSSsLCTXZHfUgEG6uOmLwmsJaANl0jhwEQ5+CnQetZwzYSFJvuHZWLSfY3Q=="
}

resource "aws_key_pair" "my-kp" {
  key_name   = "keyterra"
  public_key = var.x
}


resource "aws_security_group" "my-sg" {
  name        = "wp-sg"
  description = "alow 22 and 80 port only"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "ssh"
    from_port   = 0
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "http"
    from_port   = 0
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    protocol   = "tcp"
    from_port  = 2049
    to_port    = 2049
    cidr_blocks = ["0.0.0.0/0"]
  } 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name ="my-sg"
  }
}

resource "aws_instance" "my-ins" {
  ami           = "ami-00b494a3f139ba61f"
  availability_zone = "ap-south-1b"
  instance_type = "t2.micro"
  subnet_id = "${aws_subnet.pub-sub.id}"
  vpc_security_group_ids = ["${aws_security_group.my-sg.id}"]
  key_name = "keyterra"
  tags = {
    Name = "my-ins"
  }
  provisioner "remote-exec" {
  connection {
    type     = "ssh"
    user     = "ec2-user"
    port     =  22
    private_key = file("C:/Users/hp/Desktop/terracode/for_key/myfirstkey.pem")
    host     = aws_instance.my-ins.public_ip
  }
    inline = [
      "sudo yum install httpd git amazon-efs-utils nfs-utils php -y ", 
      "sudo systemctl restart httpd", 
      "sudo systemctl enable httpd",
      ]
 }
}



resource "aws_efs_file_system" "my-efs" {
  depends_on = [
    aws_instance.my-ins
  ]
  creation_token = "mytoken"


  tags = {
    Name = "my-efs"
  }
}


resource "aws_efs_mount_target" "alpha" {
  depends_on =  [
                aws_efs_file_system.my-efs
  ] 
  file_system_id = "${aws_efs_file_system.my-efs.id}"
  subnet_id      = aws_instance.my-ins.subnet_id
  security_groups = [ "${aws_security_group.my-sg.id}" ]

}



resource "null_resource" "nul-1"  {


depends_on = [
    aws_efs_mount_target.alpha
  ]

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/hp/Desktop/terracode/for_key/myfirstkey.pem")
    host     = aws_instance.my-ins.public_ip
  }


provisioner "remote-exec" {
    inline = [
      "sudo mount -t myefs '${aws_efs_file_system.my-efs.id}':/ /var/www/html",
      "sudo echo '${aws_efs_file_system.my-efs.id}:/ /var/www/html myefs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Sanjayde/s3.git /var/www/html/" 
    ]
  }
}

resource "aws_s3_bucket" "my-buck" {

  depends_on = [null_resource.nul-1]

  bucket = "azeeb420"

  acl = "public-read"

  force_destroy = true

}

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_s3_bucket_object" "object" {

  depends_on = [aws_s3_bucket.my-buck]

  bucket = "azeeb420"

  key = "Screenshot.png"

  source = "Screenshot.png"

  acl = "public-read"

}



resource "aws_cloudfront_distribution" "s3_distrib" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }
enabled             = true
origin {
        domain_name = aws_s3_bucket.my-buck.bucket_regional_domain_name
        origin_id   = local.s3_origin_id
    }
restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }
viewer_certificate {
        cloudfront_default_certificate = true
    }

connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.my-ins.public_ip
        port    = 22
        private_key = file("C:/Users/hp/Desktop/terracode/for_key/myfirstkey.pem")
    }
provisioner "remote-exec" {
          
              inline = [
                   "sudo su << EOF",
            "echo \"<center><img src='http://${self.domain_name}/${aws_s3_bucket_object.object.key}' height='200px' width='200px'></center>\" >> /var/www/html/index.php",
            "EOF"
       
        ]
      }
}


























