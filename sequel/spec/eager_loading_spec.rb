require File.join(File.dirname(__FILE__), "spec_helper")

describe Sequel::Model, "#eager" do
  before(:each) do
    MODEL_DB.reset
    
    class EagerAlbum < Sequel::Model(:albums)
      columns :id, :band_id
      many_to_one :band, :class=>'EagerBand', :key=>:band_id
      one_to_many :tracks, :class=>'EagerTrack', :key=>:album_id
      many_to_many :genres, :class=>'EagerGenre', :left_key=>:album_id, :right_key=>:genre_id, :join_table=>:ag
    end

    class EagerBand < Sequel::Model(:bands)
      columns :id
      one_to_many :albums, :class=>'EagerAlbum', :key=>:band_id, :eager=>:tracks
      many_to_many :members, :class=>'EagerBandMember', :left_key=>:band_id, :right_key=>:member_id, :join_table=>:bm
    end
    
    class EagerTrack < Sequel::Model(:tracks)
      columns :id, :album_id
      many_to_one :album, :class=>'EagerAlbum', :key=>:album_id
    end
    
    class EagerGenre < Sequel::Model(:genres)
      columns :id
      many_to_many :albums, :class=>'EagerAlbum', :left_key=>:genre_id, :right_key=>:album_id, :join_table=>:ag
    end
    
    class EagerBandMember < Sequel::Model(:members)
      columns :id
      many_to_many :bands, :class=>'EagerBand', :left_key=>:member_id, :right_key=>:band_id, :join_table=>:bm, :order =>:id
    end
    
    EagerAlbum.dataset.extend(Module.new {
      def fetch_rows(sql)
        h = {:id => 1, :band_id=> 2}
        h.merge!(:x_foreign_key_x=>4) if sql =~ /ag\.genre_id/
        @db << sql
        yield h
      end
    })

    EagerBand.dataset.extend(Module.new {
      def fetch_rows(sql)
        h = {:id => 2}
        h.merge!(:x_foreign_key_x=>5) if sql =~ /bm\.member_id/
        @db << sql
        yield h
      end
    })
    
    EagerTrack.dataset.extend(Module.new {
      def fetch_rows(sql)
        @db << sql
        yield({:id => 3, :album_id => 1})
      end
    })
    
    EagerGenre.dataset.extend(Module.new {
      def fetch_rows(sql)
        h = {:id => 4}
        h.merge!(:x_foreign_key_x=>1) if sql =~ /ag\.album_id/
        @db << sql
        yield h
      end
    })
    
    EagerBandMember.dataset.extend(Module.new {
      def fetch_rows(sql)
        h = {:id => 5}
        h.merge!(:x_foreign_key_x=>2) if sql =~ /bm\.band_id/
        @db << sql
        yield h
      end
    })
  end
  
  it "should eagerly load a single many_to_one association" do
    a = EagerAlbum.eager(:band).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    MODEL_DB.sqls.should == ['SELECT * FROM albums', 'SELECT * FROM bands WHERE (id IN (2))']
    a = a.first
    a.band.should be_a_kind_of(EagerBand)
    a.band.values.should == {:id => 2}
    MODEL_DB.sqls.length.should == 2
  end
  
  it "should eagerly load a single one_to_many association" do
    a = EagerAlbum.eager(:tracks).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    MODEL_DB.sqls.should == ['SELECT * FROM albums', 'SELECT * FROM tracks WHERE (album_id IN (1))']
    a = a.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(EagerTrack)
    a.tracks.first.values.should == {:id => 3, :album_id=>1}
    MODEL_DB.sqls.length.should == 2
  end
  
  it "should eagerly load a single many_to_many association" do
    a = EagerAlbum.eager(:genres).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    MODEL_DB.sqls.length.should == 2
    MODEL_DB.sqls[0].should == 'SELECT * FROM albums'
    ["SELECT genres.*, ag.album_id AS x_foreign_key_x FROM genres INNER JOIN ag ON (ag.genre_id = genres.id) AND (ag.album_id IN (1))",
     "SELECT genres.*, ag.album_id AS x_foreign_key_x FROM genres INNER JOIN ag ON (ag.album_id IN (1)) AND (ag.genre_id = genres.id)"
    ].should(include(MODEL_DB.sqls[1]))
    a = a.first
    a.genres.should be_a_kind_of(Array)
    a.genres.size.should == 1
    a.genres.first.should be_a_kind_of(EagerGenre)
    a.genres.first.values.should == {:id => 4}
    MODEL_DB.sqls.length.should == 2
  end
  
  it "should eagerly load multiple associations" do
    a = EagerAlbum.eager(:genres, :tracks, :band).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    MODEL_DB.sqls.length.should == 4
    MODEL_DB.sqls[0].should == 'SELECT * FROM albums'
    MODEL_DB.sqls[1..-1].should(include('SELECT * FROM bands WHERE (id IN (2))'))
    MODEL_DB.sqls[1..-1].should(include('SELECT * FROM tracks WHERE (album_id IN (1))'))
    sqls = MODEL_DB.sqls[1..-1] - ['SELECT * FROM bands WHERE (id IN (2))', 'SELECT * FROM tracks WHERE (album_id IN (1))']
    ["SELECT genres.*, ag.album_id AS x_foreign_key_x FROM genres INNER JOIN ag ON (ag.genre_id = genres.id) AND (ag.album_id IN (1))",
     "SELECT genres.*, ag.album_id AS x_foreign_key_x FROM genres INNER JOIN ag ON (ag.album_id IN (1)) AND (ag.genre_id = genres.id)"
    ].should(include(sqls[0]))
    a = a.first
    a.band.should be_a_kind_of(EagerBand)
    a.band.values.should == {:id => 2}
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(EagerTrack)
    a.tracks.first.values.should == {:id => 3, :album_id=>1}
    a.genres.should be_a_kind_of(Array)
    a.genres.size.should == 1
    a.genres.first.should be_a_kind_of(EagerGenre)
    a.genres.first.values.should == {:id => 4}
    MODEL_DB.sqls.length.should == 4
  end
  
  it "should allow cascading of eager loading for associations of associated models" do
    a = EagerTrack.eager(:album=>{:band=>:members}).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerTrack)
    a.first.values.should == {:id => 3, :album_id => 1}
    MODEL_DB.sqls.length.should == 4
    MODEL_DB.sqls[0...-1].should == ['SELECT * FROM tracks', 
                             'SELECT * FROM albums WHERE (id IN (1))',
                             'SELECT * FROM bands WHERE (id IN (2))']
    ["SELECT members.*, bm.band_id AS x_foreign_key_x FROM members INNER JOIN bm ON (bm.member_id = members.id) AND (bm.band_id IN (2))",
     "SELECT members.*, bm.band_id AS x_foreign_key_x FROM members INNER JOIN bm ON (bm.band_id IN (2)) AND (bm.member_id = members.id)"
    ].should(include(MODEL_DB.sqls[-1]))
    a = a.first
    a.album.should be_a_kind_of(EagerAlbum)
    a.album.values.should == {:id => 1, :band_id => 2}
    a.album.band.should be_a_kind_of(EagerBand)
    a.album.band.values.should == {:id => 2}
    a.album.band.members.should be_a_kind_of(Array)
    a.album.band.members.size.should == 1
    a.album.band.members.first.should be_a_kind_of(EagerBandMember)
    a.album.band.members.first.values.should == {:id => 5}
    MODEL_DB.sqls.length.should == 4
  end
  
  it "should cascade eagerly loading when the :eager association option is used" do
    a = EagerBand.eager(:albums).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerBand)
    a.first.values.should == {:id => 2}
    MODEL_DB.sqls.should == ['SELECT * FROM bands', 
                             'SELECT * FROM albums WHERE (band_id IN (2))',
                             'SELECT * FROM tracks WHERE (album_id IN (1))']
    a = a.first
    a.albums.should be_a_kind_of(Array)
    a.albums.size.should == 1
    a.albums.first.should be_a_kind_of(EagerAlbum)
    a.albums.first.values.should == {:id => 1, :band_id => 2}
    a = a.albums.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(EagerTrack)
    a.tracks.first.values.should == {:id => 3, :album_id => 1}
    MODEL_DB.sqls.length.should == 3
  end
  
  it "should respect :eager when lazily loading an association" do
    a = EagerBand.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerBand)
    a.first.values.should == {:id => 2}
    MODEL_DB.sqls.should == ['SELECT * FROM bands']
    a = a.first
    a.albums
    MODEL_DB.sqls.should == ['SELECT * FROM bands', 
                             'SELECT * FROM albums WHERE (band_id = 2)',
                             'SELECT * FROM tracks WHERE (album_id IN (1))']
    a.albums.should be_a_kind_of(Array)
    a.albums.size.should == 1
    a.albums.first.should be_a_kind_of(EagerAlbum)
    a.albums.first.values.should == {:id => 1, :band_id => 2}
    a = a.albums.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(EagerTrack)
    a.tracks.first.values.should == {:id => 3, :album_id => 1}
    MODEL_DB.sqls.length.should == 3
  end
  
  it "should respect :order when eagerly loading" do
    a = EagerBandMember.eager(:bands).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerBandMember)
    a.first.values.should == {:id => 5}
    MODEL_DB.sqls.length.should == 2
    MODEL_DB.sqls[0].should == 'SELECT * FROM members'
    ['SELECT bands.*, bm.member_id AS x_foreign_key_x FROM bands INNER JOIN bm ON (bm.band_id = bands.id) AND (bm.member_id IN (5)) ORDER BY id',
     'SELECT bands.*, bm.member_id AS x_foreign_key_x FROM bands INNER JOIN bm ON (bm.member_id IN (5)) AND (bm.band_id = bands.id) ORDER BY id'
    ].should(include(MODEL_DB.sqls[1]))
    a = a.first
    a.bands.should be_a_kind_of(Array)
    a.bands.size.should == 1
    a.bands.first.should be_a_kind_of(EagerBand)
    a.bands.first.values.should == {:id => 2}
    MODEL_DB.sqls.length.should == 2
  end
  
  it "should populate the reciprocal many_to_one association when eagerly loading the one_to_many association" do
    a = EagerAlbum.eager(:tracks).all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(EagerAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    MODEL_DB.sqls.should == ['SELECT * FROM albums', 'SELECT * FROM tracks WHERE (album_id IN (1))']
    a = a.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(EagerTrack)
    a.tracks.first.values.should == {:id => 3, :album_id=>1}
    a.tracks.first.album.should be_a_kind_of(EagerAlbum)
    a.tracks.first.album.should == a
    MODEL_DB.sqls.length.should == 2
  end
end

describe Sequel::Model, "#eager_graph" do
  after(:all) do
    class MockDataset
      alias clone orig_clone
    end
  end

  before(:all) do
    class MockDataset
      alias orig_clone clone
      def clone(opts = {})
        c = super()
        c.opts = @opts.merge(opts)
        c.instance_variable_set(:@columns, (@columns.dup if @columns))
        c
      end
    end

    class GraphAlbum < Sequel::Model(:albums)
      dataset.opts[:from] = [:albums]
      columns :id, :band_id
      many_to_one :band, :class=>'GraphBand', :key=>:band_id
      one_to_many :tracks, :class=>'GraphTrack', :key=>:album_id
      many_to_many :genres, :class=>'GraphGenre', :left_key=>:album_id, :right_key=>:genre_id, :join_table=>:ag
    end

    class GraphBand < Sequel::Model(:bands)
      dataset.opts[:from] = [:bands]
      columns :id, :vocalist_id
      many_to_one :vocalist, :class=>'GraphBandMember', :key=>:vocalist_id
      one_to_many :albums, :class=>'GraphAlbum', :key=>:band_id
      many_to_many :members, :class=>'GraphBandMember', :left_key=>:band_id, :right_key=>:member_id, :join_table=>:bm
      many_to_many :genres, :class=>'GraphGenre', :left_key=>:band_id, :right_key=>:genre_id, :join_table=>:bg
    end
    
    class GraphTrack < Sequel::Model(:tracks)
      dataset.opts[:from] = [:tracks]
      columns :id, :album_id
      many_to_one :album, :class=>'GraphAlbum', :key=>:album_id
    end
    
    class GraphGenre < Sequel::Model(:genres)
      dataset.opts[:from] = [:genres]
      columns :id
      many_to_many :albums, :class=>'GraphAlbum', :left_key=>:genre_id, :right_key=>:album_id, :join_table=>:ag
    end
    
    class GraphBandMember < Sequel::Model(:members)
      dataset.opts[:from] = [:members]
      columns :id
      many_to_many :bands, :class=>'GraphBand', :left_key=>:member_id, :right_key=>:band_id, :join_table=>:bm
    end
  end
    
  it "should eagerly load a single many_to_one association" do
    ds = GraphAlbum.eager_graph(:band)
    ds.sql.should == 'SELECT albums.id, albums.band_id, band.id AS band_id_0, band.vocalist_id FROM albums LEFT OUTER JOIN bands band ON (band.id = albums.band_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>1, :band_id=>2, :band_id_0=>2, :vocalist_id=>3})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    a = a.first
    a.band.should be_a_kind_of(GraphBand)
    a.band.values.should == {:id => 2, :vocalist_id=>3}
  end

  it "should eagerly load a single one_to_many association" do
    ds = GraphAlbum.eager_graph(:tracks)
    ds.sql.should == 'SELECT albums.id, albums.band_id, tracks.id AS tracks_id, tracks.album_id FROM albums LEFT OUTER JOIN tracks ON (tracks.album_id = albums.id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>1, :band_id=>2, :tracks_id=>3, :album_id=>1})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    a = a.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(GraphTrack)
    a.tracks.first.values.should == {:id => 3, :album_id=>1}
  end

  it "should eagerly load a single many_to_many association" do
    ds = GraphAlbum.eager_graph(:genres)
    ds.sql.should == 'SELECT albums.id, albums.band_id, genres.id AS genres_id FROM albums LEFT OUTER JOIN ag ON (ag.album_id = albums.id) LEFT OUTER JOIN genres ON (genres.id = ag.genre_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>1, :band_id=>2, :genres_id=>4})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    a = a.first
    a.genres.should be_a_kind_of(Array)
    a.genres.size.should == 1
    a.genres.first.should be_a_kind_of(GraphGenre)
    a.genres.first.values.should == {:id => 4}
  end

  it "should eagerly load multiple associations" do 
    ds = GraphAlbum.eager_graph(:genres, :tracks, :band)
    ds.sql.should == 'SELECT albums.id, albums.band_id, genres.id AS genres_id, tracks.id AS tracks_id, tracks.album_id, band.id AS band_id_0, band.vocalist_id FROM albums LEFT OUTER JOIN ag ON (ag.album_id = albums.id) LEFT OUTER JOIN genres ON (genres.id = ag.genre_id) LEFT OUTER JOIN tracks ON (tracks.album_id = albums.id) LEFT OUTER JOIN bands band ON (band.id = albums.band_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>1, :band_id=>2, :genres_id=>4, :tracks_id=>3, :album_id=>1, :band_id_0=>2, :vocalist_id=>6})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    a = a.first
    a.band.should be_a_kind_of(GraphBand)
    a.band.values.should == {:id => 2, :vocalist_id=>6}
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(GraphTrack)
    a.tracks.first.values.should == {:id => 3, :album_id=>1}
    a.genres.should be_a_kind_of(Array)
    a.genres.size.should == 1
    a.genres.first.should be_a_kind_of(GraphGenre)
    a.genres.first.values.should == {:id => 4}
  end

  it "should allow cascading of eager loading for associations of associated models" do
    ds = GraphTrack.eager_graph(:album=>{:band=>:members})
    ds.sql.should == 'SELECT tracks.id, tracks.album_id, album.id AS album_id_0, album.band_id, band.id AS band_id_0, band.vocalist_id, members.id AS members_id FROM tracks LEFT OUTER JOIN albums album ON (album.id = tracks.album_id) LEFT OUTER JOIN bands band ON (band.id = album.band_id) LEFT OUTER JOIN bm ON (bm.band_id = band.id) LEFT OUTER JOIN members ON (members.id = bm.member_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>3, :album_id=>1, :album_id_0=>1, :band_id=>2, :members_id=>5, :band_id_0=>2, :vocalist_id=>6})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphTrack)
    a.first.values.should == {:id => 3, :album_id => 1}
    a = a.first
    a.album.should be_a_kind_of(GraphAlbum)
    a.album.values.should == {:id => 1, :band_id => 2}
    a.album.band.should be_a_kind_of(GraphBand)
    a.album.band.values.should == {:id => 2, :vocalist_id=>6}
    a.album.band.members.should be_a_kind_of(Array)
    a.album.band.members.size.should == 1
    a.album.band.members.first.should be_a_kind_of(GraphBandMember)
    a.album.band.members.first.values.should == {:id => 5}
  end
  
  it "should populate the reciprocal many_to_one association when eagerly loading the one_to_many association" do
    MODEL_DB.reset
    ds = GraphAlbum.eager_graph(:tracks)
    ds.sql.should == 'SELECT albums.id, albums.band_id, tracks.id AS tracks_id, tracks.album_id FROM albums LEFT OUTER JOIN tracks ON (tracks.album_id = albums.id)'
    def ds.fetch_rows(sql, &block)
      @db << sql
      yield({:id=>1, :band_id=>2, :tracks_id=>3, :album_id=>1})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    a = a.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(GraphTrack)
    a.tracks.first.values.should == {:id => 3, :album_id=>1}
    a.tracks.first.album.should be_a_kind_of(GraphAlbum)
    a.tracks.first.album.should == a
    MODEL_DB.sqls.length.should == 1
  end

  it "should eager load multiple associations from the same table" do
    ds = GraphBand.eager_graph(:vocalist, :members)
    ds.sql.should == 'SELECT bands.id, bands.vocalist_id, vocalist.id AS vocalist_id_0, members.id AS members_id FROM bands LEFT OUTER JOIN members vocalist ON (vocalist.id = bands.vocalist_id) LEFT OUTER JOIN bm ON (bm.band_id = bands.id) LEFT OUTER JOIN members ON (members.id = bm.member_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>2, :vocalist_id=>6, :vocalist_id_0=>6, :members_id=>5})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphBand)
    a.first.values.should == {:id => 2, :vocalist_id => 6}
    a = a.first
    a.vocalist.should be_a_kind_of(GraphBandMember)
    a.vocalist.values.should == {:id => 6}
    a.members.should be_a_kind_of(Array)
    a.members.size.should == 1
    a.members.first.should be_a_kind_of(GraphBandMember)
    a.members.first.values.should == {:id => 5}
  end

  it "should give you a graph of tables when called without .all" do 
    ds = GraphAlbum.eager_graph(:band)
    ds.sql.should == 'SELECT albums.id, albums.band_id, band.id AS band_id_0, band.vocalist_id FROM albums LEFT OUTER JOIN bands band ON (band.id = albums.band_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>1, :band_id=>2, :band_id_0=>2, :vocalist_id=>3})
    end
    ds.first.should == {:albums=>GraphAlbum.new(:id => 1, :band_id => 2), :band=>GraphBand.new(:id => 2, :vocalist_id=>3)}
  end

  it "should not drop any associated objects if the graph could not be a cartesian product" do
    ds = GraphBand.eager_graph(:members, :vocalist)
    ds.sql.should == 'SELECT bands.id, bands.vocalist_id, members.id AS members_id, vocalist.id AS vocalist_id_0 FROM bands LEFT OUTER JOIN bm ON (bm.band_id = bands.id) LEFT OUTER JOIN members ON (members.id = bm.member_id) LEFT OUTER JOIN members vocalist ON (vocalist.id = bands.vocalist_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>2, :vocalist_id=>6, :members_id=>5, :vocalist_id_0=>6})
      yield({:id=>2, :vocalist_id=>6, :members_id=>5, :vocalist_id_0=>6})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphBand)
    a.first.values.should == {:id => 2, :vocalist_id => 6}
    a = a.first
    a.vocalist.should be_a_kind_of(GraphBandMember)
    a.vocalist.values.should == {:id => 6}
    a.members.should be_a_kind_of(Array)
    a.members.size.should == 2
    a.members.first.should be_a_kind_of(GraphBandMember)
    a.members.first.values.should == {:id => 5}
    a.members.last.should be_a_kind_of(GraphBandMember)
    a.members.last.values.should == {:id => 5}
  end

  it "should drop duplicate items that occur in sequence if the graph could be a cartesian product" do
    ds = GraphBand.eager_graph(:members, :genres)
    ds.sql.should == 'SELECT bands.id, bands.vocalist_id, members.id AS members_id, genres.id AS genres_id FROM bands LEFT OUTER JOIN bm ON (bm.band_id = bands.id) LEFT OUTER JOIN members ON (members.id = bm.member_id) LEFT OUTER JOIN bg ON (bg.band_id = bands.id) LEFT OUTER JOIN genres ON (genres.id = bg.genre_id)'
    def ds.fetch_rows(sql, &block)
      yield({:id=>2, :vocalist_id=>6, :members_id=>5, :genres_id=>7})
      yield({:id=>2, :vocalist_id=>6, :members_id=>5, :genres_id=>8})
      yield({:id=>2, :vocalist_id=>6, :members_id=>6, :genres_id=>7})
      yield({:id=>2, :vocalist_id=>6, :members_id=>6, :genres_id=>8})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphBand)
    a.first.values.should == {:id => 2, :vocalist_id => 6}
    a = a.first
    a.members.should be_a_kind_of(Array)
    a.members.size.should == 2
    a.members.first.should be_a_kind_of(GraphBandMember)
    a.members.first.values.should == {:id => 5}
    a.members.last.should be_a_kind_of(GraphBandMember)
    a.members.last.values.should == {:id => 6}
    a.genres.size.should == 2
    a.genres.first.should be_a_kind_of(GraphGenre)
    a.genres.first.values.should == {:id => 7}
    a.genres.last.should be_a_kind_of(GraphGenre)
    a.genres.last.values.should == {:id => 8}
  end

  it "should be able to be used in combination with #eager" do
    MODEL_DB.reset
    ds = GraphAlbum.eager_graph(:tracks).eager(:genres)
    def ds.fetch_rows(sql, &block)
      @db << sql
      yield({:id=>1, :band_id=>2, :tracks_id=>3, :album_id=>1})
    end
    ds2 = GraphGenre.dataset
    def ds2.fetch_rows(sql, &block)
      @db << sql
      yield({:id=>6, :x_foreign_key_x=>1})
    end
    a = ds.all
    a.should be_a_kind_of(Array)
    a.size.should == 1
    a.first.should be_a_kind_of(GraphAlbum)
    a.first.values.should == {:id => 1, :band_id => 2}
    a = a.first
    a.tracks.should be_a_kind_of(Array)
    a.tracks.size.should == 1
    a.tracks.first.should be_a_kind_of(GraphTrack)
    a.tracks.first.values.should == {:id=>3, :album_id=>1}
    a.genres.should be_a_kind_of(Array)
    a.genres.size.should == 1
    a.genres.first.should be_a_kind_of(GraphGenre)
    a.genres.first.values.should == {:id=>6}
    MODEL_DB.sqls[0].should == 'SELECT albums.id, albums.band_id, tracks.id AS tracks_id, tracks.album_id FROM albums LEFT OUTER JOIN tracks ON (tracks.album_id = albums.id)'
    ["SELECT genres.*, ag.album_id AS x_foreign_key_x FROM genres INNER JOIN ag ON (ag.genre_id = genres.id) AND (ag.album_id IN (1))",
     "SELECT genres.*, ag.album_id AS x_foreign_key_x FROM genres INNER JOIN ag ON (ag.album_id IN (1)) AND (ag.genre_id = genres.id)"
    ].should(include(MODEL_DB.sqls[1]))
  end
end
