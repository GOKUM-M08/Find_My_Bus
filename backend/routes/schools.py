"""
School management endpoints.

NOTE: like routes/students.py, this file is listed in the guide's
folder structure and imported by main.py, but its contents are never
written out in the walkthrough. Basic CRUD matching the `schools`
table in database/schema.sql.
"""
from fastapi import APIRouter
from database import supabase
from pydantic import BaseModel
from typing import Optional

router = APIRouter()

class SchoolCreate(BaseModel):
    name: str
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None

@router.get("/")
def get_schools():
    """List all schools."""
    result = supabase.table("schools").select("*").execute()
    return result.data

@router.get("/{school_id}")
def get_school(school_id: str):
    """Get one school with its buses."""
    result = supabase.table("schools")\
        .select("*, buses(*)")\
        .eq("id", school_id)\
        .execute()
    return result.data[0] if result.data else {"message": "School not found"}

@router.post("/")
def create_school(school: SchoolCreate):
    """Register a new school."""
    result = supabase.table("schools").insert(school.dict()).execute()
    return result.data[0]
