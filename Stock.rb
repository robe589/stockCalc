#coding: utf-8
require 'bundler'
Bundler.require

require 'pp'

class Stock
	#指定した銘柄コードの株価等を取得
	#@param code 銘柄コード
	#@param date[Date] 取得する日付
	#@return 取得したデータ
	#nil:存在するコードではない 空配列:情報がなかった false:取得できなかった
	def self.getClosePrice(code,date)
		code=code.to_s
		#存在する銘柄コードかチェック
=begin
		if JpStock.sec2edi(:code=>code)==nil
			return [false,"errorCode"]
		end
=end
		#株価を取得
		count=0
		begin
			error=0
			begin 
				list={:code=>code,:start_date=>date,:end_date=>date}
				stockInfo=JpStock.historical_prices list
				pp stockInfo
				stockInfo=stockInfo[0]
				if stockInfo.instance_variable_defined?(:@close)
					price=stockInfo.close
				else
					return [false,"notClose"]
				end
			rescue OpenURI::HTTPError
				puts 'OpenUri::HTTPError'
				error=1
				count+=1
			end
			if count>=100
				return [false,"HTTTPError"]
			end
		end while error==1	

		return price 
	end
end

def main()
	
	stock=Stock.new
	#JpStock.brand({:update=>0})

	date=Date.new(2015,07,24)
	pp date
	#pp Stock.getClosePrice("1211",date)
	#pp Stock.getClosePrice("3237",date)
	pp Stock.getClosePrice("1334",date)
	pp Stock.getClosePrice("1380",date)
end

main()

