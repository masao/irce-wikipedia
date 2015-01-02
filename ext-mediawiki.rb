#!/usr/bin/env ruby

require "yaml"
require "mysql2"
require_relative "solr.rb"

if $0 == __FILE__
  indexer = WikipediaSolr.new
  conf = YAML.load( open "mysql.yml" )
  mysql = Mysql2::Client.new( conf )
  results = []
  idx = 0
  interval = 10000
  while idx == 0 or results.size > 0
    STDERR.puts "subset: #{ idx } .. #{ idx + interval }"
    sql = <<EOF
	select page.page_id, page.page_title, text.old_text
		from page,revision,text
		 where text.old_id = revision.rev_text_id
			and revision.rev_page = page.page_id
			and page.page_namespace = 0
			and page.page_is_redirect != 1
			and page.page_id between #{ idx } and #{ idx + interval }
EOF
    results = mysql.query( sql, cast: false )
    results.each do |row|
      title_s = mysql.escape( row["page_title"] )
      rd_sql = <<EOF
	select * from page, redirect
		where redirect.rd_title = '#{ title_s }'
			and redirect.rd_namespace = 0
			and page.page_id = redirect.rd_from
EOF
      redirects = []
      mysql.query( rd_sql ).each do |r|
        redirects << [ r["page_title"], r["rd_fragments"] ].join(" ").strip
      end
      indexer.add( id: row["page_id"], text: row["old_text"], title: row["page_title"], redirects: redirects )
      STDERR.puts [ row["page_id"], row["page_title"], redirects.join(", ") ].join( "\t" )
    end
    indexer.commit
    idx += interval
  end
end
