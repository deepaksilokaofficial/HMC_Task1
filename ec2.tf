provider "aws" {
  region     = "ap-south-1"
  profile    = "deepak"
}

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
}

resource "aws_key_pair" "generated_key" {
  key_name   = "os_key"
  public_key = tls_private_key.key_pair.public_key_openssh
  depends_on = [ tls_private_key.key_pair ]
}

resource "local_file" "file" {
  content  = "${tls_private_key.key_pair.private_key_pem}"
  filename = "my_key.pem"

  depends_on = [
    tls_private_key.key_pair
  ]
}

resource "aws_security_group" "os_sg" {
  
depends_on = [
    tls_private_key.key_pair,aws_key_pair.generated_key
  ]
  name        = "os_sg"
  description = "Allow TCP inbound traffic"
  ingress {
    description = "TCP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "os_sg"
  }
}

resource "aws_instance" "os" {
 
depends_on = [
       tls_private_key.key_pair,aws_security_group.os_sg
  ]
 
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name =  "${aws_key_pair.generated_key.key_name}"
  security_groups = ["${aws_security_group.os_sg.name}","default"]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.key_pair.private_key_pem}"
    host     = aws_instance.os.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }


  tags = {
    Name = "myos"
  }
}

resource "aws_ebs_volume" "vol" {
  availability_zone = "${aws_instance.os.availability_zone}"
  size              = 1
  
  tags = {
    Name = "ebs1"
  }
}

resource "aws_volume_attachment" "mount" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.vol.id}"
  instance_id = "${aws_instance.os.id}"
  force_detach = true
depends_on = [
       aws_ebs_volume.vol
  ]
  provisioner "remote-exec" {
    connection {
      agent       = "false"
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.key_pair.private_key_pem}"
      host        = "${aws_instance.os.public_ip}"
    }
    
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/deepaksilokaofficial/HMC_Task1.git /var/www/html/",
      "sudo systemctl  restart  httpd"
    ]
  }
}

resource "aws_s3_bucket" "siloka_bucket" {
  bucket = "siloka1"
  acl    = "public-read"
  depends_on = [ aws_instance.os ]
}

resource "aws_s3_bucket_object" "upload_1" {
  bucket = "siloka1"
  key    = "deepak.jpg"
  source = "deepak.jpg"
  acl = "public-read"
  depends_on = [
      aws_s3_bucket.siloka_bucket
  ]
}

resource "aws_cloudfront_distribution" "s3-web-distribution" {
  origin {
    domain_name = "${aws_s3_bucket.siloka_bucket.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.siloka_bucket.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 Web Distribution"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.siloka_bucket.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Name        = "os-CF-Distribution"
    Environment = "Production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket.siloka_bucket
  ]
}

