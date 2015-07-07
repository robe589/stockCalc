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
		getNikkei225CompositeList()
	else
		marketTrend()
	end
end


def getStockCodeList()	
	stockCodeList=Array.new
	for code in 1000..9999 do
		if JpStock.sec2edi(:code=> code.to_s) 
			str=code.to_s
			stockCodeList.push(str)
		end
	end
	csv=CSV.open('stockCodeList.csv',"w")
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
		puts '日経225リスト取得失敗\n'
		return false
	end
	
	csv=CSV.open('nikkei225CodeList.csv',"w")
	csv<<list.keys
	csv<<list.values
end

def getHtmlData(url)	
	html=open(url).read
	doc=Nokogiri::HTML.parse(html,nil,'utf-8')
	
	return doc
end

def marketTrend()		
	status=Hash.new
	average=Hash.new
	#株式市場全体の状態を計算
	status['nikkei225'],average['nikkei225']=calcTrend('stockCodeList.csv')	
	#日経225の状態を計算
	status['all'],average['all']=calcTrend('nikkei225CodeList.csv')	
	#表のHTMLソースを作成
	htmlSource=makeHtmlSourceMatrix(status.keys,status)
	htmlSource+=makeHtmlSourceMatrix(average.keys,average)
	#メールを送信
	sendMail(status,average,htmlSource)
	pp status
	pp average
end

#HTMLの表を作成
#@params html 表を取得するサイトのHTMLデータ
#@params list 表のデータ配列
#@return 作成したHTMLソース
def makeHtmlSourceMatrix(head,list)
	htmlSource=String.new

	matrix=Array.new
	#表のヘッドを作成
	head.insert(0,"")
	head.each_with_index do |data,i|
		matrix[i]=Array.new
		matrix[i][0]=data
	end

	pp matrix
	
	values=list.values
	values[0].keys.each do |data|
		matrix[0].push(data)
	end
	#行の幅を統一するために、ヘッダ部分の文字長を同じ長さに
	max=matrix[0].max_by{|str| str.length}.length
	matrix[0].each_with_index do |data,i|
		diff=max - data.length
		if diff>0
			matrix[0][i]=data.to_s.center(max,'-')
		end
	end
	pp matrix
	#表のデータを作成
	list.each_with_index do |(key,data),i|
		data.each_with_index do |(key1,data2),j|
			matrix[i+1][j+1]=data2
		end
	end
	pp matrix

	#表配列をHTMLソースに変換
	htmlSource+='<table border="1" width="800" style="table-layout: fixed" rules="all">'
	matrix.each do |data|
		htmlSource+='<tr>'
		data.each do |data2|
			htmlSource+='<td>'+data2.to_s+'</td>'
		end
		htmlSource+='</tr>'
	end
	htmlSource+='</table>'
end

def calcTrend(csvName)
	#前営業日を計算
	today=Date.today
	if today.wday==1#月曜日の場合
		sub=3#金曜日の株価を取得したいので、３日前
	else
		sub=1
	end
	beforeDay=today-sub
	#それぞれの銘柄の前日と当日の株価の差を計算
	subList=calcDiffPrice(beforeDay,today,csvName)
	#上昇下降銘柄数をカウント
	status,diffSum=countStockState(subList)
	#それぞれの平均を算出
	average=calcAverage(status,diffSum)

	return status,average
end

def calcDiffPrice(beforeDay,today,fileName)
	codeList=CSV.read(fileName)
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

def calcAverage(status,diffSum)
	#それぞれの平均を計算
	allAverage=(diffSum[:all]/status[:all]).round(1)
	upAverage=(status[:up] ==0) ? 0 : (diffSum[:up]/status[:up]).round(1)
	downAverage=(status[:down] ==0) ? 0 : (diffSum[:down]/status[:down]).round(1)
	average={:allAverage=>allAverage,:upAverage=>upAverage,:downAverage=>downAverage}

	return average
end

#メールを作成、送信
def sendMail(status,average,htmlSource)
	gmailSend=GmailSend.new($senderAddress,$gmailPassword)
	#送信テキストを作成
	sendText=String.new
	sendText+='全銘柄数は'+status[:all].to_s+"\t"
	sendText+='金額平均は'+average[:all].to_s+"\n"
	sendText+='上昇銘柄数は'+status[:up].to_s+"\t"
	sendText+='金額平均は'+average[:up].to_s+"\n"
	sendText+='下降銘柄数は'+status[:down].to_s+"\t"
	sendText+='金額平均は'+average[:down].to_s+"\n"
	sendText+='変化なし銘柄数は'+status[:unChange].to_s+"\t"
	#メール送信
	text_html =Mail::Part.new do
		content_type 'text/html; charset=UTF-8'
		body htmlSource
	end
	gmailSend.setHtmlPart text_html
	sendAddress='stockInfo589@gmail.com'
	subject='本日の市場状況'
	gmailSend.sendMail(sendAddress,subject,sendText)
end

main()
