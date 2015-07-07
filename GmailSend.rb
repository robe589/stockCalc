#coding: utf-8
require 'bundler'
Bundler.require

require './myid.rb'

class GmailSend
	def initialize(address,password)
		@mail = Mail.new
		@options = {:address=> "smtp.gmail.com",
					 :port   => 587,
					 :domain => "smtp.gmail.com",
					 :user_name=> address,
					 :password => password,
					 :authentication=> 'plain',
					 :enable_starttls_auto => true  }
		@mail.charset='utf-8'
		@mail.from address
	end

	def setHtmlPart(html)
		@mail.html_part=html
	end

	def sendMail(sendAddress,subject,body)
		@mail.to=sendAddress
		@mail.subject=subject
		@mail.body=body
		@mail.delivery_method(:smtp,@options)
		@mail.deliver
	end
end

=begin
gmail=GmailSend.new('ikimono.miwa589@gmail.com',$password)
gmail.sendMail('ikimono.miwa589@gmail.com','test','test')
=end
