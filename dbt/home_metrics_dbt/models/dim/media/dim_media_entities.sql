


/*
    This is an SCD2 dim model is built off of the DBT 
    snapshot media_library_snapshot.

*/

select * from {{ ref('media_library_snapshot')}}