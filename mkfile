adocs=`{ls -d docs/*.adoc}

docs/combined.xml: $adocs
    asciidoctor -b docbook docs/combined.adoc docs/combined.adoc -o $target
combined.html: $adocs
    asciidoctor -a stylesheet=docs/adoc-riak.css docs/combined.adoc -o $target
README.md: docs/combined.xml
    pandoc --toc -f docbook docs/combined.xml -t gfm -o $out

docs:V: combined.html README.md

push:V:
    git push github

