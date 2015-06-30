#coding: utf-8
require 'bundler'
Bundler.require
require 'pp'
require 'csv'
require 'date'

require './GmailSend'
require './myid'

def main()	
	command=ARGV[0]
	p command
	case command
	when '-list' then
		getStockCodeList()
	else
		codeList=CSV.read('stockCodeList.csv')
		codeList=codeList[0]
		p codeList
		
		today=Date.today
		if today.wday==1#月曜日の場合
			sub=3
		else
			sub=1
		end
		beforeday=today-sub
		subList=Hash.new
		codeList.each do |code|
			price=JpStock.historical_prices(:code=>code,:start_date=>today-sub,:end_date=>today)
			pp price
			if price[0] ==nil
				next
			end
			puts code
			pp price
			begin
				diff=price[0].close-price[1].close
			rescue NoMethodError
				diff=0;
			end
			subList[code]=diff
		end
		status={:up=>0,:down=>0,:unChange=>0,:all=>0}
		#上昇下降銘柄をカウント
		subList.each do |a,diff|
			if diff ==0
				status[:unChange]+=1
			elsif diff > 0
				status[:up]+=1
			else
				status[:down]+=1
			end
			status[:all]+=1#カウント銘柄数をカウント
		end

		gmailSend=GmailSend.new($senderAddress,$gmailPassword)

		sendText=String.new
		sendText+='全銘柄数は'+status[:all].to_s+"\n"
		sendText+='上昇銘柄数は'+status[:up].to_s+"\n"
		sendText+='下降銘柄数は'+status[:down].to_s+"\n"
		sendText+='変化なし銘柄数は'+status[:unChange].to_s+"\n"
		sendAddress='stockInfo589@gmail.com'
		subject='本日の市場状況'
		gmailSend.sendMail(sendAddress,subject,sendText)

		pp status
	end
end

def getStockCodeList()
	csv=CSV.open('stockCodeList.csv',"w")
	stockCodeList=Array.new
	for code in 1000..1500 do
		if JpStock.sec2edi(:code=> code.to_s) 
			str=code.to_s
			stockCodeList.push(str)
		end
	end
	csv<<stockCodeList
end

main()
