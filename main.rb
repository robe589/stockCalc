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
		nikkei225List=getNikkei225CompositeList()
		if nikkei225List ==false 
			puts '日経225リスト取得失敗\n'
			return -1
		end		
		margetTrend()
	end
end

def margetTrend()	
	today=Date.today
	if today.wday==1#月曜日の場合
		sub=3#金曜日の株価を取得したいので、３日前
	else
		sub=1
	end
	beforeDay=today-sub
	#それぞれの銘柄の前日と当日の株価の差を計算
	subList=calcDiffPrice(beforeDay,today)
	#上昇下降銘柄数をカウント
	status,diffSum=countStockState(subList)	
	#メールを送信
	sendMail(status,diffSum)
	pp status
end

def getStockCodeList()
	csv=CSV.open('stockCodeList.csv',"w")
	stockCodeList=Array.new
	for code in 1000..9999 do
		if JpStock.sec2edi(:code=> code.to_s) 
			str=code.to_s
			stockCodeList.push(str)
		end
	end
	csv<<stockCodeList
end

def getNikkei225CompositeList()
	page=0
	list=Hash.new
	begin
		page+=1
		isNextPage=false
		url='http://www.nikkei.com/markets/kabu/nidxprice.aspx?index=NAVE&ResultFlag=1&DisplayType=0&GCode=35,37,41,01,03,05,07,09,11,13,15,17,19,21,23,25,27,29,31,33,43,45,47,49,51,52,53,55,57,59,61,63,65,67,69,71&PageNo='
		html=getHtmlData(url+page.to_s)

		html.xpath('//div[@class="hyo-text2 padd_left5"]').each_with_index do |node,i|
			if i%2 ==0 
				@code=node.text
			else
				list[@code]=node.text
			end
		end
        
		html.xpath('//li[@class="nextPageLink"]/a').each do |i|
			isNextPage=true
		end
	end while isNextPage==true
	
	if list.length !=225
		return false
	end
	
	return list;
end

def getHtmlData(url)	
	html=open(url).read
	doc=Nokogiri::HTML.parse(html,nil,'utf-8')
	
	return doc
end

def calcDiffPrice(beforeDay,today)
	codeList=CSV.read('stockCodeList.csv')
	codeList=codeList[0]
	p codeList
	
	subList=Hash.new
	codeList.each do |code|
		begin
			error=0
			begin
				price=JpStock.historical_prices(:code=>code,:start_date=>beforeDay,:end_date=>today)
			rescue OpenURI::HTTPError
				puts 'OpenUri::HTTPError'
				error=1
			end
		end while error==1
		if price[0] ==nil
			next
		end
		puts code
		begin
			diff=price[0].close-price[1].close
		rescue NoMethodError
			diff=0;
		end
		subList[code]=diff
	end

	return subList
end 

def countStockState(subList)
	status={:up=>0,:down=>0,:unChange=>0,:all=>0}
	diffSum={:up=>0,:down=>0,:unChange=>0,:all=>0}
	#上昇下降銘柄をカウント
	subList.each do |a,diff|
		if diff ==0
			status[:unChange]+=1
			diffSum[:unChange]+=diff
		elsif diff > 0
			status[:up]+=1
			diffSum[:up]+=diff
		else
			status[:down]+=1
			diffSum[:down]+=diff
		end
		status[:all]+=1#カウント銘柄数をカウント
		diffSum[:all]+=diff
	end

	return status,diffSum
end

#メールを作成、送信
def sendMail(status,diffSum)
	gmailSend=GmailSend.new($senderAddress,$gmailPassword)

	sendText=String.new

	#それぞれの平均を計算
	allAverage=(diffSum[:all]/status[:all]).round(1)
	upAverage=(diffSum[:up]/status[:up]).round(1)
	downAverage=(diffSum[:down]/status[:down]).round(1)
	#送信テキストを作成
	sendText+='全銘柄数は'+status[:all].to_s+"\t"
	sendText+='金額平均は'+allAverage.to_s+"\n"
	sendText+='上昇銘柄数は'+status[:up].to_s+"\t"
	sendText+='金額平均は'+upAverage.to_s+"\n"
	sendText+='下降銘柄数は'+status[:down].to_s+"\t"
	sendText+='金額平均は'+downAverage.to_s+"\n"
	sendText+='変化なし銘柄数は'+status[:unChange].to_s+"\t"
	#メール送信
	sendAddress='stockInfo589@gmail.com'
	subject='本日の市場状況'
	gmailSend.sendMail(sendAddress,subject,sendText)
end

main()
