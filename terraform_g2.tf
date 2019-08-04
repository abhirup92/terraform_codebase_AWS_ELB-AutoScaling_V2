provider "aws" {
region = "us-east-2"
}

#aws_launch config for ec2 for autoscaling group
resource "aws_launch_configuration" "webcluster" {
name = "ruby_AWS_LC"
image_id= "ami-0c209b87f96c6444f"
instance_type = "t2.micro"
security_groups = ["${aws_security_group.websg.id}"]
key_name = "abhi"
user_data = <<-EOF
#!/bin/bash
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get -y update
sudo apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io
apt-cache madison docker-ce
git clone https://github.com/abhirup92/rubyONrailsG2.git
cd rubyONrailsG2/
sudo docker build -t "ruby_image" .
sudo docker run -p 3000:3000 --name "ruby_container" -t ruby_image
EOF

lifecycle {
create_before_destroy = true
}
}

resource "aws_autoscaling_group" "aws_autoscaling_group" {
name = "g2_autoscale"
launch_configuration = "${aws_launch_configuration.webcluster.name}"
availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]
min_size = 2
max_size = 4
enabled_metrics = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupTotalInstances"]
metrics_granularity="1Minute"
load_balancers= ["${aws_elb.elb1.id}"]
health_check_type = "ELB"
tag {
key = "Name"
value = "terraform-asg-example"
propagate_at_launch = true
}
}
resource "aws_autoscaling_policy" "autopolicy" {
name = "terraform-autoplicy"
scaling_adjustment = 1
adjustment_type = "ChangeInCapacity"
cooldown = 300
autoscaling_group_name = "${aws_autoscaling_group.aws_autoscaling_group.name}"
}

resource "aws_cloudwatch_metric_alarm" "cpualarm" {
alarm_name = "terraform-alarm"
comparison_operator = "GreaterThanOrEqualToThreshold"
evaluation_periods = "2"
metric_name = "CPUUtilization"
namespace = "AWS/EC2"
period = "120"
statistic = "Average"
threshold = "60"
alarm_description = "This metric monitor EC2 instance cpu utilization"
alarm_actions = ["${aws_autoscaling_policy.autopolicy.arn}"]
}


resource "aws_autoscaling_policy" "autopolicy-down" {
name = "terraform-autoplicy-down"
scaling_adjustment = -1
adjustment_type = "ChangeInCapacity"
cooldown = 300
autoscaling_group_name = "${aws_autoscaling_group.aws_autoscaling_group.name}"
}

resource "aws_cloudwatch_metric_alarm" "cpualarm-down" {
alarm_name = "terraform-alarm-down"
comparison_operator = "LessThanOrEqualToThreshold"
evaluation_periods = "2"
metric_name = "CPUUtilization"
namespace = "AWS/EC2"
period = "120"
statistic = "Average"
threshold = "10"
alarm_description = "This metric monitor EC2 instance cpu utilization"
alarm_actions = ["${aws_autoscaling_policy.autopolicy-down.arn}"]
}

resource "aws_security_group" "websg" {
name = "security_group_for_web_server"
ingress {
from_port = 3000
to_port = 3000
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}
lifecycle {
create_before_destroy = true
}
}

resource "aws_security_group" "elbsg" {
name = "security_group_for_elb"
ingress {
from_port = 3000
to_port = 3000
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}
egress {
from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"]
}
lifecycle {
create_before_destroy = true
}
}
resource "aws_elb" "elb1" {
name = "terraform-elb"
availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]
security_groups = ["${aws_security_group.elbsg.id}"]
listener {
instance_port = 3000
instance_protocol = "tcp"
lb_port = 3000
lb_protocol = "tcp"
}
health_check {
healthy_threshold = 2
unhealthy_threshold = 2
timeout = 10
target = "TCP:3000"
interval = 30
}
idle_timeout = 60
connection_draining = true
connection_draining_timeout = 120

}
output "elb-dns" {
value = "${aws_elb.elb1.dns_name}"
}