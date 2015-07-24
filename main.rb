#coding: utf-8
require 'bundler'
Bundler.require

require 'pp'
require 'csv'
require 'date'
require 'bigdecimal'

require './GmailSend'
require './myid'
require './Stock'

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
	startDate=Date.new(2015,1,1)
	endDate=Date.today

	#jpstock内部の上場企業情報を更新
	JpStock.brand({:update=>0})

	#上場企業の情報を取得
	stockInfo=JpStock.brand({})
	
	stockCodeList=Array.new
	stockInfo.each do |data|
		stockCodeList.push(data.code)
	end
	
	csv=CSV.open('stockCodeList.csv',"w")
	csv<<stockCodeList
    pp stockCodeList.length
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
	averageRatio=Hash.new
	#株式市場全体の状態を計算
	status[:all],average[:all],averageRatio[:all]=calcTrend('stockCodeList.csv')	
	#日経225の状態を計算
	status[:nikkei225],average[:nikkei225],averageRatio[:nikkei225]=calcTrend('nikkei225CodeList.csv')	
	#計算した値に数値を付与
	joinUnitToNum(status[:all],average[:all],averageRatio[:all])
	joinUnitToNum(status[:nikkei225],average[:nikkei225],averageRatio[:nikkei225])
	#表のHTMLソースを作成
	htmlSource=String.new
	htmlSource+='上昇下降銘柄表<br>'
	htmlSource+=makeHtmlSourceMatrix(status.keys,status)
	htmlSource+='株価変化平均表<br>'
	htmlSource+=makeHtmlSourceMatrix(average.keys,average)
	htmlSource+='株価変化率平均表<br>'
	htmlSource+=makeHtmlSourceMatrix(averageRatio.keys,averageRatio)
	#メールを送信
	sendMail(status,average,htmlSource)
	pp status
	pp average
end

def joinUnitToNum(status,average,averageRatio) 
	#数値に単位を付与
	status.each do |key,num|
		status[key]=num.to_s+'銘柄'
	end
	average.each do |key,num|
		average[key]=num.to_s+'円'
		if num ==0
		elsif num>0 
			average[key]+='上昇'
		else
			average[key]+='下降'
		end
	end
	averageRatio.each do |key,num|
		str=num.to_s+'%'
		averageRatio[key]=str
	end
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
	priceList=getPriceList(csvName)
	pp priceList
	#それぞれの銘柄の前日と当日の株価の差を計算
	subList=calcDiffPrice(priceList)
	#上昇下降銘柄数をカウント
	status,statusList,diffSum=countStockState(subList)
	#それぞれの平均を算出
	averagePrice=calcAverage(status,diffSum)
	#それぞれの上下降率の平均を算出
	averageRatio=calcAverageRatio(status,statusList,priceList)

	return status,averagePrice,averageRatio
end

def getPriceList(csvName)
	#前営業日を計算
	today=Date.today
	beforeDay=today-1
    pp HolidayJp.holiday?(beforeDay)
	while(HolidayJp.holiday?(beforeDay)!=nil or beforeDay.wday ==0 or beforeDay.wday ==6)
		beforeDay-=1
		pp HolidayJp.holiday?(beforeDay)
	end
	puts "beforeDay"+beforeDay.to_s	
	#銘柄リストを追加
	codeList=CSV.read(csvName)
	codeList=codeList[0]
	p codeList
	#銘柄別価格リストを作成
	priceList=Hash.new
	codeList.each do |code|
		pp code
		priceToday=Stock.getClosePrice(code,today)
		priceBefore=Stock.getClosePrice(code,beforeDay)
		if priceToday.class ==Array 
			if priceToday[1]=="notClose"
				puts '終値がついていなかった'
				next	
			elsif priceToday[1]=="HTTPError"
				puts 'HTTPError'
				return false
			elsif priceToday[1]=="errorCode"
				puts '銘柄が存在しない'
				next
			end
		end
		if priceBefore.class ==Array 
			if priceBefore[1]=="notClose"
				puts '終値がついていなかった'
				next	
			elsif priceBefore[1]=="HTTPError"
				puts 'HTTPError'
				return false
			end	
		end

		priceList[code]=Hash.new
		priceList[code][:closePricePastDay]=priceBefore
		priceList[code][:closePriceNowDay]=priceToday
	end
	
	return priceList
end

def calcDiffPrice(priceList)
		
	subList=Hash.new
	priceList.keys.each do |code|
		pp code
		begin
			diff=priceList[code][:closePriceNowDay]-priceList[code][:closePricePastDay]
		rescue NoMethodError
			diff=0;
		end
		subList[code]=diff
	end
	
	pp subList
	return subList
end 

def countStockState(subList)
	status={:up=>0,:down=>0,:unChange=>0,:all=>0}
	diffSum={:up=>0,:down=>0,:unChange=>0,:all=>0}
	statusList={:up=>[],:down=>[],:unChange=>[],:all=>[]}
	#上昇下降銘柄をカウント
	subList.each do |code,diff|
		if diff ==0
			status[:unChange]+=1
			diffSum[:unChange]+=diff
			statusList[:unChange].push(code)
		elsif diff > 0
			status[:up]+=1
			diffSum[:up]+=diff
			statusList[:up].push(code)
		else
			status[:down]+=1
			diffSum[:down]+=diff
			statusList[:down].push(code)
		end
		status[:all]+=1#カウント銘柄数をカウント
		diffSum[:all]+=diff
		statusList[:all].push(code)
	end
	
	return status,statusList,diffSum
end

def calcAverage(status,diffSum)
	#それぞれの平均を計算
	allAverage= (status[:all]==0) ? 0: (diffSum[:all]/status[:all]).round(1) 
	upAverage=(status[:up] ==0) ? 0 : (diffSum[:up]/status[:up]).round(1)
	downAverage=(status[:down] ==0) ? 0 : (diffSum[:down]/status[:down]).round(1)
	average={:allAverage=>allAverage,:upAverage=>upAverage,:downAverage=>downAverage}

	return average
end

def calcAverageRatio(status,statusList,priceList)
	ratioList=Hash.new
	addPriceList={:upRatio=>0.0,:downRatio=>0.0,:allRatio=>0.0}
	priceList.each do |key,price|
		diff=price[:closePriceNowDay]-price[:closePricePastDay]
		price[:ratio]=diff/price[:closePricePastDay]*100
		if diff>0
			addPriceList[:upRatio]+=price[:ratio]
		elsif diff<0
			addPriceList[:downRatio]+=price[:ratio]
		end
		addPriceList[:allRatio]+=price[:ratio]
	end
	
	allAverageRatio=calcRatio(addPriceList[:allRatio],status[:all])
	upAverageRatio=calcRatio(addPriceList[:upRatio],status[:up])
	downAverageRatio=calcRatio(addPriceList[:downRatio],status[:down])
		averageRatio={:allAvergeRatio=>allAverageRatio,
				  :upAverageRatio=>upAverageRatio,
				  :downAverageRatio=>downAverageRatio}

	return averageRatio
end

def calcRatio(num1,num2)
	if num2==0
		return 0
	end
	num=num1/num2
	#小数点1桁までの文字列に変換
	num=BigDecimal.new(num.to_s).floor(1).to_f.to_s
end

#メールを作成、送信
def sendMail(status,average,htmlSource)
	gmailSend=GmailSend.new($senderAddress,$gmailPassword)
	#メール送信
	text_html =Mail::Part.new do
		content_type 'text/html; charset=UTF-8'
		body htmlSource
	end
	gmailSend.setHtmlPart text_html
	sendAddress='stockInfo589@gmail.com'
	subject='本日の市場状況'
	gmailSend.sendMail(sendAddress,subject," ")
end

main()
