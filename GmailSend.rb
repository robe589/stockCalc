#coding: utf-8
require 'bundler'
Bundler.require

#require './account.rb'

class GmailSend
	@@mail = Mail.new
	def initialize(address,password)
		@@options = {:address=> "smtp.gmail.com",
					 :port   => 587,
					 :domain => "smtp.gmail.com",
					 :user_name=> address,
					 :password => password,
					 :authentication=> 'plain',
					 :enable_starttls_auto => true  }
		@@mail.charset='utf-8'
		@@mail.from address
	end

	def sendMail(sendAddress,subject,body)
		@@mail.to=sendAddress
		@@mail.subject=subject
		@@mail.body=body
		@@mail.delivery_method(:smtp,@@options)
		@@mail.deliver
	end
end

=begin
gmail=GmailSend.new('ikimono.miwa589@gmail.com',$password)
gmail.sendMail('ikimono.miwa589@gmail.com','test','test')
=end
