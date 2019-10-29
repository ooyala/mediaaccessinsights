terraform {
  backend "s3" {}
}

variable "kibana_dashboard" {
  type    = string
  default = "@../ReportTemplate/latest_dashboard1.json"
}

variable "manifest_parser" {
  type    = string
  default = "./parser/manifest_parser.rb"
}

variable "manifest_parser_dest" {
  type    = string
  default = "/home/ubuntu/logstash-7.3.1/manifest_parser.rb"
}

variable "s3accessstoredomain" {
  type    = string
  default = "s3accessstore"
}

variable "aws_region" {
  type    = string
}

variable "cf_prefix" {
  type = string
}

variable "cf_access_exclude" {
  type = string
}

variable "cf_access_key_id" {
  type = string
}

variable "cf_access_secret" {
  type = string
}
provider "aws" {
  region = var.aws_region
}

variable "cf_access_bucket" {
  type    = string
}

variable "addition_auth_keys" {
  type = list(string)
}

variable "deployer_key" {
  type = string
}

variable "logstash_ami" {
  type = string
}

variable "logstash_subnet_id" {
  type = string
}

variable "logstash_security_group_ids" {
  type = list(string)
}

variable "logstash_instance_type" {
  type = string
}

variable "ssh_private_key_path" {
  type = string
}

data "template_file" "cloudfront_conf" {
  template = file("../AccessStoreConfig/cloudfront/cloudfront.conf.template")
  vars = {
    region            = var.aws_region
    els_ep            = aws_elasticsearch_domain.s3accessstore.endpoint
    monitor_bkt       = var.cf_access_bucket
    cf_prefix         = var.cf_prefix
    cf_access_exclude = var.cf_access_exclude
    cf_access_key_id  = var.cf_access_key_id
    cf_access_secret  = var.cf_access_secret
    parser_file       = var.manifest_parser_dest
    index_name        = "object_access_cf"
    template          = "cloudfront.template.json"
    grok_pattern      = "%%{DATE_EU:date}\\t%%{TIME:time}\\t(?<x_edge_location>\\b[\\w\\-]+\\b)\\t(?:%%{NUMBER:sc_bytes:int}|-)\\t%%{IPORHOST:c_ip}\\t%%{WORD:cs_method}\\t%%{HOSTNAME:cs_host}\\t%%{NOTSPACE:cs_uri_stem}\\t%%{NUMBER:sc_status:int}\\t%%{GREEDYDATA:referrer}\\t%%{GREEDYDATA:User_Agent}\\t%%{GREEDYDATA:cs_uri_query}\\t%%{GREEDYDATA:cookies}\\t%%{WORD:x_edge_result_type}\\t%%{NOTSPACE:x_edge_request_id}\\t%%{HOSTNAME:x_host_header}\\t%%{URIPROTO:cs_protocol}\\t%%{INT:cs_bytes:int}\\t%%{NUMBER:time_taken:float}\\t%%{NOTSPACE:x_forwarded_for}\\t%%{NOTSPACE:ssl_protocol}\\t%%{NOTSPACE:ssl_cipher}\\t%%{NOTSPACE:x_edge_response_result_type}"
    date_time         = "%%{date} %%{time}"
  }
}

resource "local_file" "cloudfrontconfigfile" {
  content  = data.template_file.cloudfront_conf.rendered
  filename = "../AccessStoreConfig/cloudfront/cloudfront.conf"
}

variable "access_index" {
  type    = string
  default = <<EOF
{
      "settings" : {
        "index" : {
          "number_of_shards" : 3,
          "number_of_replicas" : 1
        }
      }
    }
EOF

}

variable "access_mapping" {
  type    = string
  default = <<EOF
{
   "dynamic_templates":[
      {
         "strings":{
            "mapping":{
               "type":"keyword"
            },
            "match_mapping_type":"string",
            "match":"*"
         }
      }
   ],
   "properties":{
      "access_timestamp":{
         "type":"date"
      },
      "geoip":{
         "properties":{
            "location":{
               "type":"geo_point"
            },
            "ip":{
               "type":"ip"
            }
         }
      }
   }
}
EOF

}

variable "transition_index" {
  type    = string
  default = <<EOF
{
    "settings" : {
        "index" : {
            "number_of_shards" : 3,
            "number_of_replicas" : 1
        }
    }
}
EOF

}

variable "transition_mapping" {
  type    = string
  default = <<EOF
{
    "properties": {
      "access_timestamp":     { "type": "date"  },
      "bucket":  {"type":   "keyword"},
      "object_key": {"type":   "keyword"},
      "storage_class": {"type":   "keyword"},
      "bucket_region": {"type":   "keyword"}
     }
}
EOF

}

locals {
  logstash_ssh_keys = join("\n", var.addition_auth_keys)
}

output "logstash_ssh_keys" {
  value = join("\n", var.addition_auth_keys)
}

# Elastic search creation for access data store
# TODO: commenting it out as it would take more time to create; Comment only when you "DESTORY"
data "aws_region" "current" {
}

data "aws_caller_identity" "current" {
}

resource "aws_elasticsearch_domain" "s3accessstore" {
  domain_name = var.s3accessstoredomain
  cluster_config {
    instance_count         = 2
    dedicated_master_count = 1
    zone_awareness_enabled = false
    instance_type          = "t2.medium.elasticsearch"
  }
  ebs_options {
    ebs_enabled = true
    volume_type = "gp2"
    volume_size = 10
  }
  encrypt_at_rest {
    enabled = false
  }
  elasticsearch_version = "7.1"
  access_policies       = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "es:*",
      "Principal": "*",
      "Effect": "Allow",
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.s3accessstoredomain}/*",
      "Condition": {
        "IpAddress": {"aws:SourceIp": ["0.0.0.0/0"]}
      }
    }
  ]
}
POLICY


  provisioner "local-exec" {
    command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_access -H 'content-type: application/json' -d '${var.access_index}'"
  }
  provisioner "local-exec" {
    command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_access/_mapping/insert_object_access?include_type_name=true -H 'content-type: application/json' -d '${var.access_mapping}'"
  }
  provisioner "local-exec" {
    command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_transition -H 'content-type: application/json' -d '${var.transition_index}'"
  }
  provisioner "local-exec" {
    command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_transition/_mapping/insert_object_transition?include_type_name=true -H 'content-type: application/json' -d '${var.transition_mapping}'"
  }
  #provisioner "local-exec" {
  #command = "curl -X POST https://${aws_elasticsearch_domain.s3accessstore.kibana_endpoint}/api/kibana/dashboards/import -H 'content-type: application/json' -H 'kbn-xsrf: true' -d '${var.kibana_dashboard}'"
  #}
}

# Create logstash Instance
resource "aws_key_pair" "deployer" {
  key_name   = "key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCWYrBibfXw8iBUCWFTKXVtQJwGCc2iRjKNMBhHoZOdSW8RzZlqGDzPTDPr4kWlEGEHSsugtK/yirHCAq586siExU3I0UjhXvkGmjnfx1PwVl58BYiDf8DWQx4Dvlbgnwp68UBAzyE3m6gP4Wj/8Wx6I3QKIhQgttEDeTfqEgMeykn7PiHRKd0QZZ2nLIskRS5xDNhFyUYcv65t3gqaokDHU/1kz0ppk3yA4zifNTQEHcxSe4b2ItP3QlAiAxa+mXQDg34ai4vcVokILn3Zki/uZt3QfvZ1lZ/CO2iIyOXmGbPmk98ln4lbsnvWcAyc4ARCYwUsNBpZntnAulkP9R2UNPjq8QiqSc6QoRALekZhbLzu0SoglbDW3N1bnntdmNMieKUCQPX+A9NeCecbNymFyTtNKkKElQYF0n8cNtKvxT7FhZrihw9dHOmW2oVAj7/FMbiwCwz/pmcPqW0WNYs2qk+utzmm31ipI3VLofIZyClbqXxL+KEX21CRtzrHKFHcOJssjdk0KmkTH7frKkGG4G+97fQcQhAxLhMYIhtjEvs85+p6EC1i4DewBSgMmo5axbdQpwuY7MrGwxL5jFhEOTbRKuHudTB+ArMy5Tn1l8fk/h9c9kE6sVON93MZJZQUnfC8MPdm11TXniuIdLo5p2cpzpyiCWPyz71mQEgqRQ== maheshwarang@vpn-client-38.sv2"
}

resource "aws_iam_role" "accessstorerole" {
  name               = "accessstorerole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy" "s3access" {
  name   = "s3access"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        }
    ]
}
POLICY

}

resource "aws_iam_policy" "esfullaccess" {
  name   = "esfullaccess"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "es:*"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
POLICY

}

resource "aws_iam_role_policy_attachment" "s3attach" {
  policy_arn = aws_iam_policy.s3access.arn
  role       = aws_iam_role.accessstorerole.name
}

resource "aws_iam_role_policy_attachment" "esattach" {
  policy_arn = aws_iam_policy.esfullaccess.arn
  role       = aws_iam_role.accessstorerole.name
}

resource "aws_iam_instance_profile" "accessstoreprofile" {
  name = "accessstoreprofilename"
  role = aws_iam_role.accessstorerole.name
}

resource "aws_instance" "cflogcollector" {
  ami                         = var.logstash_ami
  instance_type               = var.logstash_instance_type
  count                       = "1"
  key_name                    = "key"
  subnet_id                   = var.logstash_subnet_id
  vpc_security_group_ids      = var.logstash_security_group_ids
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.accessstoreprofile.name
  tags = {
    Name = "Logstash/CFLogCollector"
  }
  provisioner "file" {
    source      = "../AccessStoreConfig/cloudfront/cloudfront.template.json"
    destination = "/tmp/cloudfront.template.json"
  }
  provisioner "file" {
    source      = local_file.cloudfrontconfigfile.filename
    destination = "/tmp/cloudfront.conf"
  }
  provisioner "file" {
    source      = "../AccessStoreConfig/parser/manifest_parser.rb"
    destination = "/tmp/manifest_parser.rb"
  }
  provisioner "file" {
    source      = "../AccessStoreConfig/GeoLite2-City_20190903/GeoLite2-City.mmdb"
    destination = "/tmp/GeoLite2-City.mmdb"
  }
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = self.public_ip
    agent       = false
  }
  timeouts {
    create = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y upgrade",
      "sudo apt-get install -y default-jdk",
      "sudo apt-get install -y ffmpeg",
      "sudo echo \"${local.logstash_ssh_keys}\" >> ~/.ssh/authorized_keys",
      "sudo echo \"JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64\" >> /etc/environment",
      "wget https://artifacts.elastic.co/downloads/logstash/logstash-7.3.1.tar.gz",
      "tar xvf logstash-7.3.1.tar.gz",
      "cd logstash-7.3.1",
      "bin/logstash-plugin install logstash-output-amazon_es",
      "sudo cp /tmp/cloudfront.template.json cloudfront.template.json",
      "sudo cp /tmp/cloudfront.conf cloudfront.conf",
      "sudo cp /tmp/manifest_parser.rb ${var.manifest_parser_dest}",
      "sudo cp /tmp/GeoLite2-City.mmdb /home/ubuntu/logstash-7.3.1/vendor/bundle/jruby/2.5.0/gems/logstash-filter-geoip-6.0.1-java/vendor",
      "nohup bin/logstash -f cloudfront.conf &",
      "sleep 120",
      "echo \"Completed the Logstash deployment!!\"",
    ]
  }
  provisioner "local-exec" {
      command = "curl -X POST https://${aws_elasticsearch_domain.s3accessstore.kibana_endpoint}/api/kibana/dashboards/import -H 'content-type: application/json' -H 'kbn-xsrf: true' -d '${var.kibana_dashboard}'"
  }
}

